// Network access helpers
// Resolves which circles a user is allowed to see places from:
// their own circles, circles shared with them, their accepted connections'
// public/myNetwork circles, the innerCircle circles of connections who put them
// on their Inner Circle list, and FOLLOWED users' public circles (following is
// one-way, so it earns the public tier only — myNetwork stays connections-only).

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('../services/idService');

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

/**
 * Everyone whose Inner Circle list contains `userId`.
 *
 * Asked from the viewer's side on purpose: one array-contains query on a
 * single-field index, rather than loading every owner's list while building a
 * feed. Grantors are always accepted connections, since that is enforced when
 * the list is written.
 */
async function getInnerCircleGrantorIds(userId) {
  if (!userId) return new Set();
  const snapshot = await db.collection(COLLECTIONS.USERS)
    .where('innerCircle', 'array-contains', String(userId))
    .select()
    .get();
  return new Set(snapshot.docs.map(doc => doc.id));
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
    const [connectedUserIds, innerCircleGrantors] = await Promise.all([
      getConnectedUserIds(userId),
      getInnerCircleGrantorIds(userId)
    ]);
    let privacies = null;
    if (connectedUserIds.has(connectionId)) {
      privacies = ['public', 'myNetwork'];
      // Only if this particular person put the viewer on their list.
      if (innerCircleGrantors.has(connectionId)) privacies.push('innerCircle');
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
  const [connectedUserIds, ownCircles, sharedCircles, userDoc, innerCircleGrantors] = await Promise.all([
    getConnectedUserIds(userId),
    db.collection(COLLECTIONS.CIRCLES).where('owner', '==', userId).get(),
    db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', userId).get(),
    db.collection(COLLECTIONS.USERS).doc(userId).get(),
    getInnerCircleGrantorIds(userId)
  ]);
  ownCircles.docs.forEach(addCircle);
  sharedCircles.docs.forEach(addCircle);

  // Followed-only ids = following minus accepted connections (they already
  // get the higher tier above)
  const following = (userDoc.exists && userDoc.data().following) || [];
  const followedOnlyIds = following.filter(id => id && id !== userId && !connectedUserIds.has(id));

  // Phase 2 — connections' public/myNetwork circles, the innerCircle circles of
  // the connections who listed this viewer, and followed users' public circles
  // Only connections may grant inner-circle access, so a grantor who is no
  // longer a connection has already lost it — intersect rather than trust the
  // stored list. Normalised on both sides: grantors are user doc ids while
  // connections come off connection docs, and Apple accounts write those two
  // in different shapes.
  const connectedNormalized = new Set(Array.from(connectedUserIds).map(normalizeUserId));
  const activeGrantors = Array.from(innerCircleGrantors)
    .filter(id => connectedNormalized.has(normalizeUserId(id)));

  const [connectionDocs, innerCircleDocs, followedDocs] = await Promise.all([
    circlesByOwners(Array.from(connectedUserIds), ['public', 'myNetwork']),
    circlesByOwners(activeGrantors, ['innerCircle']),
    circlesByOwners(followedOnlyIds, ['public'])
  ]);
  connectionDocs.forEach(addCircle);
  innerCircleDocs.forEach(addCircle);
  followedDocs.forEach(addCircle);

  return { circleIds: Array.from(circleIds) };
}

module.exports = { getAllowedCircleIds, getConnectedUserIds, getFollowedOnlyUserIds, getInnerCircleGrantorIds };
