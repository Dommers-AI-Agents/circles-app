// Venues whose loyalty program is live: the set the Locals tab may show
// (offers, announcements, store events). Shared by GET /rewards/offers and
// the nearby-events aggregator so both apply the same gate.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { isOwnerPremiumForVenue, isCompActive } = require('./ownerSubscriptionService');

/**
 * Active sticker venues with loyalty live: an explicit comp OR a premium
 * owner (the owner's subscription covers only the venue it was bought
 * for). Lapsed owners' offers AND announcements are hidden alike.
 */
async function listLiveVenues() {
  const db = getFirestore();
  // Single equality filter — served by the automatic index
  const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
    .where('active', '==', true)
    .limit(200)
    .get();
  const allVenues = snapshot.docs.map((doc) => ({ venueId: doc.id, ...doc.data() }));
  const ownerIds = [...new Set(allVenues.map((v) => v.ownerUserId).filter(Boolean))];
  const ownerUsers = new Map();
  if (ownerIds.length > 0) {
    const ownerDocs = await db.getAll(...ownerIds.map((id) => db.collection(COLLECTIONS.USERS).doc(id)));
    ownerDocs.forEach((doc) => { if (doc.exists) ownerUsers.set(doc.id, doc.data()); });
  }
  return allVenues.filter((venue) =>
    isCompActive(venue) || isOwnerPremiumForVenue(ownerUsers.get(venue.ownerUserId), venue.venueId, venue)
  );
}

module.exports = { listLiveVenues };
