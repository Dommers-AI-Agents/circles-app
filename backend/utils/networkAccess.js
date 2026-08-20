// Network access helpers
// Resolves which circles a user is allowed to see places from:
// their own circles, circles shared with them, their accepted connections'
// public/myNetwork circles, and FOLLOWED users' public circles (following is
// one-way, so it earns the public tier only — myNetwork stays connections-only).

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

/** Accepted-connection user ids, both directions. */
async function getConnectedUserIds(userId) {
  const [connectionsQuery1, connectionsQuery2] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get(),
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get()
  ]);

  const connectedUserIds = new Set();
  connectionsQuery1.docs.forEach(doc => connectedUserIds.add(doc.data().connectedUserId));
  connectionsQuery2.docs.forEach(doc => connectedUserIds.add(doc.data().userId));
  return connectedUserIds;
}

/** Ids the user follows (from their user doc), excluding any in `exclude`. */
async function getFollowedOnlyUserIds(userId, exclude = new Set()) {
  const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
  const following = (userDoc.exists && userDoc.data().following) || [];
  return following.filter(id => id && id !== userId && !exclude.has(id));
}

/** Batched owner-in + privacy-in circle query (10 owners per batch keeps the
 *  disjunction count under Firestore's 30 limit). */
async function circlesByOwners(ownerIds, privacies) {
  if (ownerIds.length === 0) return [];
  const batches = [];
  for (let i = 0; i < ownerIds.length; i += 10) {
    batches.push(ownerIds.slice(i, i + 10));
  }
  const results = await Promise.all(
    batches.map(batch =>
      db.collection(COLLECTIONS.CIRCLES)
        .where('owner', 'in', batch)
        .where('privacy', 'in', privacies)
        .get()
    )
  );
  return results.flatMap(snapshot => snapshot.docs);
}

/**
 * Get all circle IDs whose places the user is allowed to see.
 *
 * @param {string} userId - Firebase UID of the requesting user
 * @param {object} [options]
 * @param {string|null} [options.connectionId] - If set, restrict to circles
 *   owned by this user. Must be an accepted connection (public + myNetwork
 *   tiers) or a followed user (public tier only) — otherwise empty.
 * @param {boolean} [options.mapOnly] - If true, drop circles whose owner set
 *   showOnMap === false (their map-clutter opt-out, e.g. bulk-import circles).
 *   Missing showOnMap counts as visible.
 * @returns {Promise<{circleIds: string[]}>}
 */
async function getAllowedCircleIds(userId, { connectionId = null, mapOnly = false } = {}) {
  const circleIds = new Set();
  const addCircle = (doc) => {
    if (mapOnly && doc.data().showOnMap === false) return;
    circleIds.add(doc.id);
  };

  if (connectionId) {
    // Restrict to a single person; tier depends on the relationship
    const connectedUserIds = await getConnectedUserIds(userId);
    let privacies = null;
    if (connectedUserIds.has(connectionId)) {
      privacies = ['public', 'myNetwork'];
    } else {
      const followedIds = await getFollowedOnlyUserIds(userId, connectedUserIds);
      if (followedIds.includes(connectionId)) privacies = ['public'];
    }
    if (!privacies) return { circleIds: [] };

    const docs = await circlesByOwners([connectionId], privacies);
    docs.forEach(addCircle);
    return { circleIds: Array.from(circleIds) };
  }

  // Phase 1 — every independent read at once: the connection pair, own
  // circles, circles shared with the user, and the user doc (following list).
  // These were previously four sequential await phases.
  const [connectedUserIds, ownCircles, sharedCircles, userDoc] = await Promise.all([
    getConnectedUserIds(userId),
    db.collection(COLLECTIONS.CIRCLES).where('owner', '==', userId).get(),
    db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', userId).get(),
    db.collection(COLLECTIONS.USERS).doc(userId).get()
  ]);
  ownCircles.docs.forEach(addCircle);
  sharedCircles.docs.forEach(addCircle);

  // Followed-only ids = following minus accepted connections (they already
  // get the higher tier above)
  const following = (userDoc.exists && userDoc.data().following) || [];
  const followedOnlyIds = following.filter(id => id && id !== userId && !connectedUserIds.has(id));

  // Phase 2 — connections' public/myNetwork circles + followed users' public circles
  const [connectionDocs, followedDocs] = await Promise.all([
    circlesByOwners(Array.from(connectedUserIds), ['public', 'myNetwork']),
    circlesByOwners(followedOnlyIds, ['public'])
  ]);
  connectionDocs.forEach(addCircle);
  followedDocs.forEach(addCircle);

  return { circleIds: Array.from(circleIds) };
}

module.exports = { getAllowedCircleIds, getConnectedUserIds, getFollowedOnlyUserIds };
