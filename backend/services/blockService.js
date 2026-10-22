// backend/services/blockService.js
//
// Blocking one person, for every surface that offers it (the profile's Block,
// the Dog Park's Block on a post). Moved out of blockController so a widget
// endpoint can block without a controller importing a controller.
//
// A block means "we never see each other again": an audit row in BLOCKS,
// connections marked blocked, block state denormalized onto both user docs
// (blockedUsers on the blocker, blockedBy on the blocked — what every feed
// filters on), and follows and Inner Circle grants severed both ways.
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');

/**
 * @returns {Promise<{ alreadyBlocked: boolean, block: object|null }>}
 */
async function block(blockerId, blockedUserId, { db = getFirestore() } = {}) {
  if (!blockedUserId) throw new ServiceError(400, 'invalid_user', 'Pick someone to block');
  if (blockerId === blockedUserId) throw new ServiceError(400, 'self_block', 'You cannot block yourself');

  const userDoc = await db.collection(COLLECTIONS.USERS).doc(blockedUserId).get();
  if (!userDoc.exists) throw new ServiceError(404, 'user_not_found', 'User not found');

  const existing = await db.collection(COLLECTIONS.BLOCKS)
    .where('blockerId', '==', blockerId)
    .where('blockedUserId', '==', blockedUserId)
    .get();
  if (!existing.empty) return { alreadyBlocked: true, block: null };

  const now = new Date().toISOString();
  const blockRef = await db.collection(COLLECTIONS.BLOCKS).add({ blockerId, blockedUserId, createdAt: now, updatedAt: now });
  const createdBlock = serializeDoc(await blockRef.get());

  const [connections1, connections2] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', blockerId).where('connectedUserId', '==', blockedUserId).get(),
    db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', blockedUserId).where('connectedUserId', '==', blockerId).get()
  ]);

  const FieldValue = admin.firestore.FieldValue;
  const batch = db.batch();
  [...connections1.docs, ...connections2.docs].forEach((doc) => {
    batch.update(doc.ref, { status: 'blocked', blockedBy: blockerId, updatedAt: now });
  });
  batch.update(db.collection(COLLECTIONS.USERS).doc(blockerId), {
    blockedUsers: FieldValue.arrayUnion(blockedUserId),
    following: FieldValue.arrayRemove(blockedUserId),
    followers: FieldValue.arrayRemove(blockedUserId),
    innerCircle: FieldValue.arrayRemove(blockedUserId),
    updatedAt: now
  });
  batch.update(db.collection(COLLECTIONS.USERS).doc(blockedUserId), {
    blockedBy: FieldValue.arrayUnion(blockerId),
    following: FieldValue.arrayRemove(blockerId),
    followers: FieldValue.arrayRemove(blockerId),
    innerCircle: FieldValue.arrayRemove(blockerId),
    updatedAt: now
  });
  await batch.commit();

  // Follower counts drift if left to increments — recompute both from the
  // arrays just rewritten (array length is the source of truth).
  try {
    const [a, b] = await Promise.all([
      db.collection(COLLECTIONS.USERS).doc(blockerId).get(),
      db.collection(COLLECTIONS.USERS).doc(blockedUserId).get()
    ]);
    await Promise.all([a, b].map((doc) => doc.ref.update({
      followersCount: (doc.data().followers || []).length,
      followingCount: (doc.data().following || []).length
    })));
  } catch (countError) {
    console.warn('Block follower-count resync failed:', countError.message);
  }

  return { alreadyBlocked: false, block: createdBlock };
}

module.exports = { block };
