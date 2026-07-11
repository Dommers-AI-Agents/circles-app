// backend/services/activityFeedService.js
// Scalable network activity fetching.
//
// The old approach scanned the latest N activities PLATFORM-WIDE and then
// filtered to the user's network. As platform activity grows, other users'
// activity pushes your network's items out of that window and the feed goes
// falsely empty. Instead, query directly by actor using the
// (actorId ASC, timestamp DESC) composite index - the same index already
// used by activityController's getActivities - chunked to Firestore's
// 30-value 'in' limit. Reads scale with the user's network size, never with
// total platform activity.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeQuerySnapshot } = require('../models/FirestoreModels');
const db = getFirestore();

const IN_QUERY_CHUNK = 30; // Firestore 'in' operator max values
const MAX_ACTORS = 600;    // caps fan-out at 20 parallel indexed queries

const toMillis = (t) => {
  if (!t) return 0;
  if (typeof t.toMillis === 'function') return t.toMillis();
  if (t._seconds !== undefined) return t._seconds * 1000;
  return new Date(t).getTime() || 0;
};

/**
 * Fetch the most recent activities performed by the given actors, newest first.
 *
 * @param {Iterable<string>} actorIds - user ids whose activities to fetch
 * @param {number} limit - max activities to return
 * @returns {Promise<Array>} serialized activity docs sorted by timestamp desc
 */
exports.fetchActivitiesByActors = async (actorIds, limit) => {
  let actors = Array.from(actorIds);
  if (actors.length === 0 || limit <= 0) return [];

  if (actors.length > MAX_ACTORS) {
    console.warn(`⚠️ [ActivityFeed] Truncating actor list ${actors.length} -> ${MAX_ACTORS}`);
    actors = actors.slice(0, MAX_ACTORS);
  }

  const chunks = [];
  for (let i = 0; i < actors.length; i += IN_QUERY_CHUNK) {
    chunks.push(actors.slice(i, i + IN_QUERY_CHUNK));
  }

  try {
    const snapshots = await Promise.all(chunks.map(chunk =>
      db.collection(COLLECTIONS.ACTIVITIES)
        .where('actorId', 'in', chunk)
        .orderBy('timestamp', 'desc')
        .limit(limit) // any single chunk could satisfy the whole feed
        .get()
    ));

    return snapshots
      .flatMap(snapshot => serializeQuerySnapshot(snapshot))
      .sort((a, b) => toMillis(b.timestamp) - toMillis(a.timestamp))
      .slice(0, limit);
  } catch (error) {
    // Most likely a missing composite index - degrade to the old global scan
    // rather than erroring the whole home screen
    console.error('❌ [ActivityFeed] Actor-scoped query failed, falling back to global scan:', error.message);
    const snapshot = await db.collection(COLLECTIONS.ACTIVITIES)
      .orderBy('timestamp', 'desc')
      .limit(Math.max(limit * 3, 60))
      .get();
    const actorSet = new Set(actors);
    return serializeQuerySnapshot(snapshot)
      .filter(activity => actorSet.has(activity.actorId))
      .slice(0, limit);
  }
};
