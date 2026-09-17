// backend/services/placeCommentService.js
//
// Writes a comment on a venue: the placeComments doc (keyed by the canonical
// globalPlaceId, placeId kept for legacy readers), the venue's commentsCount,
// the first-comment FavCoin, the owner notification and the feed row. Shared
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

  // Feed row (best-effort). activityController is the established writer.
  // Skipped for check-in notes — the check-in row already tells the story.
  if (!trackActivity) return { comment, piggyBank };
  try {
    let circleName = null;
    if (place.circleId) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
      circleName = circleDoc.exists ? (circleDoc.data().name || null) : null;
    }
    const { createActivity } = require('../controllers/activityController');
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

module.exports = { postPlaceComment };
