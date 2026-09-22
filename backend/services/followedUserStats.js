// Activity stats for users someone follows but is not connected to: whether
// they added a place in the last 7 days, and how many places they have. The
// people row asks for these for every followed-only user; done one user at a
// time they cost ~150 ms each (4.6 s for 30 users), so they run in parallel,
// a batch of users at a time to keep the fan-out bounded.
const { COLLECTIONS } = require('../models/FirestoreModels');
const { chunk } = require('../utils/firestoreChunks');

const RECENT_DAYS = 7;
const USERS_PER_BATCH = 20;

const statsFor = async (db, userId, since) => {
  const placesBy = db.collection(COLLECTIONS.PLACES).where('addedBy', '==', userId);
  const [recent, total] = await Promise.all([
    placesBy.where('createdAt', '>', since).limit(1).get(),
    placesBy.count().get(),
  ]);
  return { hasRecentPlace: !recent.empty, totalPlaces: total.data().count || 0 };
};

// Balanced scoring for followed users: activity earns points, existence does not.
const scoreFor = ({ hasRecentPlace, totalPlaces }) => {
  let score = hasRecentPlace ? 30 : 0;
  if (totalPlaces > 10) score += 15;
  else if (totalPlaces > 5) score += 10;
  else if (totalPlaces > 0) score += 5;
  return score;
};

// Returns Map<userId, { hasRecentPlace, totalPlaces, score }>.
const followedUserStats = async (db, userIds, now = Date.now()) => {
  const since = new Date(now - RECENT_DAYS * 24 * 60 * 60 * 1000);
  const out = new Map();
  for (const batch of chunk(userIds, USERS_PER_BATCH)) {
    const rows = await Promise.all(batch.map((id) => statsFor(db, id, since)));
    batch.forEach((id, i) => out.set(id, { ...rows[i], score: scoreFor(rows[i]) }));
  }
  return out;
};

module.exports = { followedUserStats, scoreFor, RECENT_DAYS, USERS_PER_BATCH };
