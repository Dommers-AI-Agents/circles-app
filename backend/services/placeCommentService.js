// backend/services/placeCommentService.js
//
// Writes a comment on a venue: the placeComments doc (keyed by the canonical
// globalPlaceId, placeId kept for legacy readers), the venue's commentsCount,
// the first-comment FavCoin, the saver's and store team's notifications and the feed row. Shared
// by POST /places/:id/comments and by check-ins that carry a note
// ("the patio is great after 6" belongs on the place, not just in the feed).
// Permission checks stay with the caller.
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, createPlaceComment } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');
const { projectPublicUser } = require('./publicUserProjection');
const notificationService = require('./notificationService');
const piggyBankService = require('./piggyBankService');
const { ServiceError } = require('../utils/serviceError');
const { nowIso } = require('../utils/ids');
const { commentPermissions, MAX_COMMENT_LENGTH } = require('./placeCommentRules');

const db = getFirestore();

// Returns { comment, piggyBank }. `source` is stamped on the comment
// ('check_in') so the place page can label it later; absent for plain comments.
async function postPlaceComment({ placeDoc, userId, text, source = null, checkInId = null, trackActivity = true }) {
  const place = serializeDoc(placeDoc);
  const trimmed = String(text || '').trim();
  if (!trimmed) throw new Error('Comment text is required');

  const commentGlobalPlaceId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
  const commentData = {
    ...createPlaceComment({ placeId: placeDoc.id, userId, text: trimmed }),
    globalPlaceId: commentGlobalPlaceId || null,
    ...(source ? { source } : {}),
    ...(checkInId ? { checkInId } : {})
  };

  const commentRef = await db.collection('placeComments').add(commentData);

  if (commentGlobalPlaceId) {
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(commentGlobalPlaceId).update({
      commentsCount: admin.firestore.FieldValue.increment(1)
    }).catch((err) => console.error('⚠️ Failed to bump commentsCount:', err.message));
  }

  const comment = serializeDoc(await commentRef.get());

  // 1 FavCoin for your first comment on someone else's venue (per-venue dedup)
  let piggyBank = null;
  if (place.addedBy !== userId) {
    piggyBank = await piggyBankService.credit({
      userId,
      eventType: 'place_comment',
      sourceRef: { commentId: commentRef.id, globalPlaceId: commentGlobalPlaceId || null, placeId: placeDoc.id }
    });
  }

  const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
  if (userDoc.exists) comment.user = projectPublicUser(serializeDoc(userDoc));

  if (place.addedBy !== userId) {
    await notificationService.sendPlaceCommentNotification(place.addedBy, userId, placeDoc.id, place.name, trimmed)
      .catch((err) => console.error('⚠️ Comment notification failed:', err.message));
  }
  // A claimed store's team hears about comments on it (reviews, 2026-11-02)
  require('./storeFeedback').notifyTeamOfComment({ globalPlaceId: commentGlobalPlaceId, place, placeId: placeDoc.id, commenterId: userId, text: trimmed })
    .catch((err) => console.error('⚠️ Team comment notification failed:', err.message));

  // Feed row (best-effort). activityController is the established writer.
  // Skipped for check-in notes — the check-in row already tells the story.
  if (!trackActivity) return { comment, piggyBank };
  try {
    let circleName = null;
    if (place.circleId) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
      circleName = circleDoc.exists ? (circleDoc.data().name || null) : null;
    }
    const { createActivity } = require('./activity/createActivity');
    await createActivity('place_commented', userId, 'place', placeDoc.id, place.name || 'Unknown Place', {
      circleId: place.circleId || null,
      circleName: circleName || 'Unknown Circle',
      comment: trimmed,
      commentId: commentRef.id,
      placePhoto: place.photos && place.photos.length > 0 ? place.photos[0] : null,
      placeAddress: place.address || null
    });
  } catch (err) {
    console.error('⚠️ place_commented activity failed:', err.message);
  }

  return { comment, piggyBank };
}

// New words on a comment, by its author (Wes, 2026-11-24). Likes, replies,
// the coin and the notifications it earned stay as they were; `editedAt`
// marks it. The feed row that quotes the comment gets the new words too. A
// check-in's own note is the record of that visit and is left alone.
async function editPlaceComment({ placeId, commentId, userId, text }) {
  const trimmed = String(text || '').trim();
  if (!trimmed) throw new ServiceError(400, 'TEXT_REQUIRED', 'Comment text is required');
  if (trimmed.length > MAX_COMMENT_LENGTH) {
    throw new ServiceError(400, 'TEXT_TOO_LONG', `Keep it under ${MAX_COMMENT_LENGTH} characters`);
  }
  const commentRef = db.collection('placeComments').doc(commentId);
  const [commentDoc, placeDoc] = await Promise.all([
    commentRef.get(),
    db.collection(COLLECTIONS.PLACES).doc(placeId).get()
  ]);
  if (!commentDoc.exists) throw new ServiceError(404, 'COMMENT_NOT_FOUND', 'Comment not found');
  if (!placeDoc.exists) throw new ServiceError(404, 'PLACE_NOT_FOUND', 'Place not found');
  const comment = serializeDoc(commentDoc);
  const place = serializeDoc(placeDoc);
  const { belongs, canEdit } = commentPermissions({ comment, place, placeId, userId });
  if (!belongs) throw new ServiceError(400, 'WRONG_PLACE', 'Comment does not belong to this place');
  if (!canEdit) throw new ServiceError(403, 'NOT_AUTHOR', 'Only the person who wrote a comment can edit it');

  const before = comment.text || null;
  if (before !== trimmed) {
    await commentRef.update({ text: trimmed, editedAt: nowIso() });
    // The feed quotes the comment: same lookup as a delete (commentId on new
    // rows, the old words on rows from before it was stamped)
    try {
      const hits = await db.collection('activities')
        .where('type', '==', 'place_commented')
        .where('actorId', '==', String(comment.userId))
        .where('targetId', '==', comment.placeId)
        .get();
      const byId = hits.docs.filter((doc) => doc.data().metadata?.commentId === commentId);
      const matches = byId.length > 0
        ? byId
        : hits.docs.filter((doc) => !doc.data().metadata?.commentId && (doc.data().metadata?.comment || null) === before);
      await Promise.all(matches.map((doc) => doc.ref.update({ 'metadata.comment': trimmed, 'metadata.commentId': commentId })));
    } catch (err) {
      console.error('⚠️ Edited comment: feed row not updated:', err.message);
    }
  }

  const updated = serializeDoc(await commentRef.get());
  const userDoc = await db.collection(COLLECTIONS.USERS).doc(String(comment.userId)).get();
  if (userDoc.exists) updated.user = projectPublicUser(serializeDoc(userDoc));
  return updated;
}

module.exports = { postPlaceComment, editPlaceComment };
