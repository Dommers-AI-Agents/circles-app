// services/storeCustomers.js
//
// A store's customers, as its team sees them (Wes, 2026-11-02). Rewards are
// small giveaways on the honor system; what keeps them fair is that the store
// knows who's earning:
//   * Claiming a reward shares your name, photo and email with that store
//     (`sharedWithStore`, asked once per store before the first reward).
//   * The team's Customers list: purchases scanned, rewards claimed, last
//     visit — email only for people who shared it.
//   * "Remove from rewards": that store's points go to 0 and the person stops
//     earning there; "Restore" gives the points back.
//
// Everything lives on the customer's bucket for the store,
// users/{uid}.rewardPointsByVenue.{venueId}: points, venueName, purchases,
// rewardsClaimed, lastScanAt, sharedWithStore, removedFromRewards,
// removedPoints, countsBackfilled.

const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');

const db = () => getFirestore();
const userRef = (userId) => db().collection(COLLECTIONS.USERS).doc(String(userId));
const bucketOf = (userData, venueId) => ((userData && userData.rewardPointsByVenue) || {})[venueId] || null;
const field = (venueId, name) => `rewardPointsByVenue.${venueId}.${name}`;

async function isRemoved(userId, venueId) {
  const doc = await userRef(userId).get();
  return !!(doc.exists && (bucketOf(doc.data(), venueId) || {}).removedFromRewards);
}

/** The customer agrees to share name, photo and email with this store. */
async function shareWithStore(userId, venue) {
  await userRef(userId).update({
    [field(venue.venueId, 'sharedWithStore')]: new Date().toISOString(),
    [field(venue.venueId, 'venueName')]: venue.venueName || null
  });
}

/** Purchases / rewards / last scan from the ledger, for buckets from before the counters. */
async function countsFromLedger(userId, venueId) {
  const snap = await db().collection(STICKER_COLLECTIONS.REWARD_EVENTS)
    .where('userId', '==', userId).where('venueId', '==', venueId).get();
  let purchases = 0; let rewardsClaimed = 0; let lastScanAt = null;
  snap.forEach((d) => {
    const e = d.data();
    if (e.type === 'venue_visit') {
      purchases += 1;
      if (!lastScanAt || String(e.createdAt) > lastScanAt) lastScanAt = e.createdAt;
    } else if (e.type === 'redemption') rewardsClaimed += 1;
  });
  return { purchases, rewardsClaimed, lastScanAt };
}

/** Everyone holding a bucket at this store, most recent visit first. */
async function listCustomers(venue) {
  const { isHiddenAccount } = require('./hiddenAccounts');
  const snap = await db().collection(COLLECTIONS.USERS)
    .where(field(venue.venueId, 'points'), '>=', 0).limit(1000).get();
  const rows = [];
  for (const doc of snap.docs) {
    const user = doc.data();
    if (isHiddenAccount(user)) continue;
    let bucket = bucketOf(user, venue.venueId) || {};
    if (!bucket.countsBackfilled) {
      const counts = await countsFromLedger(doc.id, venue.venueId);
      await doc.ref.update({
        [field(venue.venueId, 'purchases')]: counts.purchases,
        [field(venue.venueId, 'rewardsClaimed')]: counts.rewardsClaimed,
        [field(venue.venueId, 'lastScanAt')]: counts.lastScanAt,
        [field(venue.venueId, 'countsBackfilled')]: true
      });
      bucket = { ...bucket, ...counts };
    }
    rows.push({
      user: {
        id: doc.id,
        displayName: user.displayName || 'FavCircles user',
        username: user.username || null,
        profilePicture: user.profilePicture || null
      },
      email: bucket.sharedWithStore ? (user.email || null) : null,
      sharedWithStore: !!bucket.sharedWithStore,
      points: bucket.points || 0,
      purchases: bucket.purchases || 0,
      rewardsClaimed: bucket.rewardsClaimed || 0,
      lastScanAt: bucket.lastScanAt || null,
      removed: !!bucket.removedFromRewards
    });
  }
  return rows.sort((a, b) => String(b.lastScanAt || '').localeCompare(String(a.lastScanAt || '')));
}

/** Take someone off this store's rewards: points to 0 (kept for Restore), no more earning. */
async function removeCustomer(venue, userId) {
  await db().runTransaction(async (tx) => {
    const doc = await tx.get(userRef(userId));
    const bucket = doc.exists ? bucketOf(doc.data(), venue.venueId) : null;
    if (!bucket) throw new ServiceError(404, 'not_found', 'That person has no rewards here.');
    if (bucket.removedFromRewards) return;
    const points = bucket.points || 0;
    tx.update(doc.ref, {
      rewardPoints: FieldValue.increment(-points),
      [field(venue.venueId, 'points')]: 0,
      [field(venue.venueId, 'removedPoints')]: points,
      [field(venue.venueId, 'removedFromRewards')]: new Date().toISOString()
    });
  });
  require('./rewardService').walletBalanceChanged(userId, venue.venueId);
}

/** Undo: points back, earning again. */
async function restoreCustomer(venue, userId) {
  await db().runTransaction(async (tx) => {
    const doc = await tx.get(userRef(userId));
    const bucket = doc.exists ? bucketOf(doc.data(), venue.venueId) : null;
    if (!bucket || !bucket.removedFromRewards) return;
    const points = bucket.removedPoints || 0;
    tx.update(doc.ref, {
      rewardPoints: FieldValue.increment(points),
      [field(venue.venueId, 'points')]: FieldValue.increment(points),
      [field(venue.venueId, 'removedPoints')]: FieldValue.delete(),
      [field(venue.venueId, 'removedFromRewards')]: FieldValue.delete()
    });
  });
  require('./rewardService').walletBalanceChanged(userId, venue.venueId);
}

module.exports = { isRemoved, shareWithStore, listCustomers, removeCustomer, restoreCustomer, countsFromLedger };
