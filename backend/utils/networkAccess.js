// Network access helpers
// Resolves which circles a user is allowed to see places from:
// their own circles, circles shared with them, and their accepted
// connections' public/myNetwork circles.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

/**
 * Get all circle IDs whose places the user is allowed to see.
 *
 * @param {string} userId - Firebase UID of the requesting user
 * @param {object} [options]
 * @param {string|null} [options.connectionId] - If set, restrict to circles
 *   owned by this user. Must be an accepted connection of userId (otherwise
 *   an empty result is returned).
 * @returns {Promise<{circleIds: string[]}>}
 */
async function getAllowedCircleIds(userId, { connectionId = null } = {}) {
  const circleIds = new Set();

  // Accepted connections in both directions
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

  if (connectionId) {
    // Restrict to a single connection; verify it actually is one
    if (!connectedUserIds.has(connectionId)) {
      return { circleIds: [] };
    }

    const connectionCircles = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', connectionId)
      .where('privacy', 'in', ['public', 'myNetwork'])
      .get();
    connectionCircles.docs.forEach(doc => circleIds.add(doc.id));
    return { circleIds: Array.from(circleIds) };
  }

  // Own circles (all privacies) and circles explicitly shared with the user
  const [ownCircles, sharedCircles] = await Promise.all([
    db.collection(COLLECTIONS.CIRCLES).where('owner', '==', userId).get(),
    db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', userId).get()
  ]);
  ownCircles.docs.forEach(doc => circleIds.add(doc.id));
  sharedCircles.docs.forEach(doc => circleIds.add(doc.id));

  // Connections' public/myNetwork circles, batched by 10 owners
  // (10 owners * 2 privacy values = 20 disjunctions, under Firestore's 30 limit)
  if (connectedUserIds.size > 0) {
    const ownerArray = Array.from(connectedUserIds);
    const batches = [];
    for (let i = 0; i < ownerArray.length; i += 10) {
      batches.push(ownerArray.slice(i, i + 10));
    }

    const results = await Promise.all(
      batches.map(batch =>
        db.collection(COLLECTIONS.CIRCLES)
          .where('owner', 'in', batch)
          .where('privacy', 'in', ['public', 'myNetwork'])
          .get()
      )
    );
    results.forEach(snapshot => snapshot.docs.forEach(doc => circleIds.add(doc.id)));
  }

  return { circleIds: Array.from(circleIds) };
}

module.exports = { getAllowedCircleIds };
