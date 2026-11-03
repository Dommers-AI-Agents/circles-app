// services/scanAttempts.js
//
// Register scans that earned nothing, one row per attempt (Wes, 2026-11-03):
// an owner checking scans against their security cameras sees every time
// someone scanned the register code, not only the ones that paid. Kept out of
// rewardEvents so a customer's points history stays points only.
//
//   scan_far      the phone was clearly away from the store
//   scan_repeat   already earned at this store today
//   scan_removed  the store took them off its rewards
//
// The owner's Activity merges these with rewardEvents (venueActivityFeed).

const { getFirestore } = require('../config/firebase');
const { newId, nowIso } = require('../utils/ids');

const SCAN_ATTEMPTS = 'scanAttempts';
const OUTCOME_TYPES = { far: 'scan_far', already_today: 'scan_repeat', removed: 'scan_removed' };

/** The attempt's row type for a scan that didn't earn, or null when it isn't one we log. */
const attemptType = (reason) => OUTCOME_TYPES[reason] || null;

async function recordScanAttempt(userId, venue, { reason, location = null }) {
  const type = attemptType(reason);
  if (!type) return null;
  const row = {
    userId: String(userId),
    venueId: venue.venueId,
    venueName: venue.venueName || null,
    type,
    points: 0,
    location,
    createdAt: nowIso()
  };
  await getFirestore().collection(SCAN_ATTEMPTS).doc(newId()).set(row);
  return row;
}

/**
 * A store's Activity page: reward events and scan attempts newest first,
 * `limit` rows before `before` (an ISO time) when given.
 */
async function venueActivityFeed(venueId, rewardEventsCollection, { limit, before = null }) {
  const page = (collection) => {
    let query = getFirestore().collection(collection)
      .where('venueId', '==', venueId)
      .orderBy('createdAt', 'desc')
      .limit(limit);
    if (before) query = query.startAfter(String(before));
    return query.get();
  };
  const [events, attempts] = await Promise.all([page(rewardEventsCollection), page(SCAN_ATTEMPTS)]);
  return [...events.docs, ...attempts.docs]
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, limit);
}

module.exports = { recordScanAttempt, venueActivityFeed, attemptType, SCAN_ATTEMPTS };
