// services/storeFeedback.js
//
// "Enjoying <store>?" (Wes, 2026-11-02): once per store, after a reward is
// given, the customer is asked — never in exchange for the reward — to
//   * write a review of the store on FavCircles (a public comment on the place),
//   * follow the store (its announcements reach their feed),
//   * tell the store privately (1–5 stars and a note only the team reads),
//   * post a moment there.
// Asked once per store: `rewardPointsByVenue.<venueId>.enjoyingAskedAt`.
// Private feedback lives in `storeFeedback` (one doc per person per store per
// day, so a second send that day replaces the first) and pushes the team.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { isSameUser } = require('./idService');

const FEEDBACK = 'storeFeedback';
const MAX_NOTE = 1000;
const db = () => getFirestore();

async function loadVenue(venueId) {
  const doc = await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId)).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'Store not found');
  return { venueId: doc.id, ...doc.data() };
}

/**
 * A save of this store the customer may comment on: their own, else the
 * oldest one whose circle they can open (the gate the comments endpoint
 * applies). Null when there's none.
 */
async function reviewSaveId(userId, venue, globalPlaceId) {
  const own = await require('./ownSaveOfVenue').findOwnSaveOfStore({ userId, venue });
  if (own) return own.id;
  if (!globalPlaceId) return null;
  const snap = await db().collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', globalPlaceId).get();
  const { pickRepresentativeSave } = require('./representativeSave');
  const { canViewCircleFor } = require('./circleAccess');
  const chosen = await pickRepresentativeSave(snap.docs.map(serializeDoc), userId, async (save) => {
    if (!save.circleId) return true;
    const circle = await db().collection(COLLECTIONS.CIRCLES).doc(save.circleId).get();
    return circle.exists ? canViewCircleFor(serializeDoc(circle), userId) : false;
  });
  return chosen ? (chosen.id || chosen._id) : null;
}

/**
 * The card, the first time only: { show: false } after that. Asking marks it
 * asked, so it never comes back for this store.
 */
async function enjoyingCard(userId, venueId) {
  const venue = await loadVenue(venueId);
  const userRef = db().collection(COLLECTIONS.USERS).doc(String(userId));
  const userDoc = await userRef.get();
  const bucket = ((userDoc.exists && userDoc.data().rewardPointsByVenue) || {})[venue.venueId] || {};
  if (bucket.enjoyingAskedAt) return { show: false };
  await userRef.update({ [`rewardPointsByVenue.${venue.venueId}.enjoyingAskedAt`]: new Date().toISOString() });

  const globalPlaceId = await require('./venueHelpers').venueGlobalPlaceId(venue);
  let following = false;
  if (globalPlaceId) {
    const gp = await db().collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId)).get();
    following = gp.exists && (gp.data().followers || []).some((id) => isSameUser(id, userId));
  }
  return {
    show: true,
    venueName: venue.venueName || 'this store',
    globalPlaceId: globalPlaceId || null,
    reviewPlaceId: await reviewSaveId(userId, venue, globalPlaceId).catch(() => null),
    following
  };
}

/** Private feedback: 1–5 stars and an optional note, for the store's team only. */
async function sendFeedback(userId, venueId, { rating, note } = {}) {
  const stars = Number(rating);
  if (!Number.isInteger(stars) || stars < 1 || stars > 5) {
    throw new ServiceError(400, 'invalid_rating', 'Pick 1 to 5 stars.');
  }
  const text = String(note || '').trim().slice(0, MAX_NOTE);
  const venue = await loadVenue(venueId);
  const now = new Date().toISOString();
  await db().collection(FEEDBACK).doc(`${venue.venueId}__${userId}__${now.slice(0, 10)}`).set({
    venueId: venue.venueId, userId: String(userId), rating: stars, note: text || null, createdAt: now
  });

  const userDoc = await db().collection(COLLECTIONS.USERS).doc(String(userId)).get();
  const name = (userDoc.exists && userDoc.data().displayName) || 'A customer';
  const team = [venue.ownerUserId, ...require('./venueHelpers').venueManagerIds(venue)].filter(Boolean);
  const { sendInBackground } = require('./notifyQuiet');
  [...new Set(team.map(String))].forEach((memberId) => sendInBackground(memberId, {
    type: 'store_feedback',
    title: `${'★'.repeat(stars)}${'☆'.repeat(5 - stars)} from ${name}`,
    body: text ? text.slice(0, 120) : `Private feedback for ${venue.venueName}`,
    data: { type: 'store_feedback', venueId: venue.venueId }
  }, 'store feedback'));
  return { sent: true };
}

/** The team's view, newest first, with who sent it. */
async function listFeedback(venue, limit = 200) {
  const snap = await db().collection(FEEDBACK).where('venueId', '==', venue.venueId)
    .orderBy('createdAt', 'desc').limit(limit).get();
  const rows = snap.docs.map((d) => d.data());
  const ids = [...new Set(rows.map((r) => r.userId))];
  const docs = ids.length ? await db().getAll(...ids.map((id) => db().collection(COLLECTIONS.USERS).doc(id))) : [];
  const cards = new Map(docs.filter((d) => d.exists).map((d) => [d.id, {
    id: d.id, displayName: d.data().displayName || 'FavCircles user', profilePicture: d.data().profilePicture || null
  }]));
  return rows.map((r) => ({ rating: r.rating, note: r.note || null, createdAt: r.createdAt, user: cards.get(r.userId) || null }));
}

/** New public comments on a claimed store reach its team too (Wes, 2026-11-02: reviews on FavCircles). */
async function notifyTeamOfComment({ globalPlaceId, place, placeId, commenterId, text }) {
  if (!globalPlaceId) return;
  const venue = await require('./placePhotoService').venueForPlace(globalPlaceId, place);
  if (!venue || !venue.ownerUserId) return;
  const team = [venue.ownerUserId, ...require('./venueHelpers').venueManagerIds(venue)].filter(Boolean).map(String);
  const skip = [commenterId, place.addedBy].filter(Boolean);   // the saver already got one
  const notificationService = require('./notificationService');
  for (const memberId of new Set(team)) {
    if (skip.some((id) => isSameUser(id, memberId))) continue;
    await notificationService.sendPlaceCommentNotification(memberId, commenterId, placeId, venue.venueName || place.name, text)
      .catch((e) => console.error('⚠️ team comment notification failed:', e.message));
  }
}

module.exports = { enjoyingCard, sendFeedback, listFeedback, notifyTeamOfComment, reviewSaveId };
