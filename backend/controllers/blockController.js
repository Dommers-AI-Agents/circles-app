const { admin, getFirestore } = require('../config/firebase');
const { sendServiceError } = require('../utils/serviceError');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { projectPublicUser } = require('../services/publicUserProjection');

const db = getFirestore();

// @desc    Block a user
// @route   POST /api/blocks/user/:userId
// @access  Private
const blockUser = async (req, res) => {
  try {
    const blockerId = req.user.firebaseDocId || req.user.uid;
    const { alreadyBlocked, block } = await require('../services/blockService').block(blockerId, req.params.userId, { db });
    if (alreadyBlocked) {
      return res.status(400).json({
        success: false,
        message: 'User is already blocked'
      });
    }
    res.status(201).json({
      success: true,
      message: 'User blocked successfully',
      block
    });
  } catch (error) {
    if (error && error.status && error.status < 500) {
      return res.status(error.status).json({ success: false, message: error.message });
    }
    sendServiceError(res, error, { log: 'Error blocking user', fallbackMessage: 'Failed to block user' });
  }
};

// @desc    Unblock a user
// @route   DELETE /api/blocks/user/:userId
// @access  Private
const unblockUser = async (req, res) => {
  try {
    const blockerId = req.user.firebaseDocId || req.user.uid;
    const blockedUserId = req.params.userId;

    // Find the block document
    const blockQuery = await db.collection(COLLECTIONS.BLOCKS)
      .where('blockerId', '==', blockerId)
      .where('blockedUserId', '==', blockedUserId)
      .get();

    if (blockQuery.empty) {
      return res.status(404).json({
        success: false,
        message: 'Block not found'
      });
    }

    // Delete the block document
    const batch = db.batch();
    blockQuery.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    // Update any connections that were blocked
    const connectionQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', blockerId)
      .where('connectedUserId', '==', blockedUserId)
      .where('status', '==', 'blocked')
      .get();

    const connectionQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', blockedUserId)
      .where('connectedUserId', '==', blockerId)
      .where('status', '==', 'blocked')
      .get();

    // Remove the blocked status from connections (disconnect them)
    [...connectionQuery1.docs, ...connectionQuery2.docs].forEach(doc => {
      batch.delete(doc.ref);
    });

    // Clear the denormalized block state. Follows stay severed — unblocking
    // makes someone visible again, it doesn't resurrect the relationship.
    batch.update(db.collection(COLLECTIONS.USERS).doc(blockerId), {
      blockedUsers: admin.firestore.FieldValue.arrayRemove(blockedUserId),
      updatedAt: new Date().toISOString()
    });
    batch.update(db.collection(COLLECTIONS.USERS).doc(blockedUserId), {
      blockedBy: admin.firestore.FieldValue.arrayRemove(blockerId),
      updatedAt: new Date().toISOString()
    });

    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'User unblocked successfully'
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error unblocking user', fallbackMessage: 'Failed to unblock user' });
  }
};

// @desc    Get list of blocked users
// @route   GET /api/blocks
// @access  Private
const getBlockedUsers = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
    const { startAfter } = req.query;

    // Equality-only and sorted here: the old orderBy needed a composite index
    // that was never created, so the list always failed (500). A person's
    // block list is short.
    const snapshot = await db.collection(COLLECTIONS.BLOCKS).where('blockerId', '==', userId).limit(1000).get();
    const all = snapshot.docs.map(serializeDoc).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
    const from = startAfter ? all.findIndex((b) => b.id === startAfter) + 1 : 0;
    const page = all.slice(from, from + limit);
    const blocks = [];

    // The blocked person as a public card only — this returned their whole
    // user doc (email, phone, device tokens) to the blocker
    for (const block of page) {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(block.blockedUserId).get();
      if (userDoc.exists) {
        block.blockedUser = { ...projectPublicUser(serializeDoc(userDoc)), _id: userDoc.id, id: userDoc.id };
      }
      blocks.push(block);
    }
    const hasMoreBlocks = from + limit < all.length;

    res.status(200).json({
      success: true,
      blocks,
      hasMore: hasMoreBlocks
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error fetching blocked users', fallbackMessage: 'Failed to fetch blocked users' });
  }
};

// @desc    Check if a user is blocked
// @route   GET /api/blocks/check/:userId
// @access  Private
const checkIfBlocked = async (req, res) => {
  try {
    const checkerId = req.user.firebaseDocId || req.user.uid;
    const targetUserId = req.params.userId;

    // Check if current user has blocked target user
    const blockedByMeQuery = await db.collection(COLLECTIONS.BLOCKS)
      .where('blockerId', '==', checkerId)
      .where('blockedUserId', '==', targetUserId)
      .get();

    // Check if target user has blocked current user
    const blockedMeQuery = await db.collection(COLLECTIONS.BLOCKS)
      .where('blockerId', '==', targetUserId)
      .where('blockedUserId', '==', checkerId)
      .get();

    res.status(200).json({
      success: true,
      isBlockedByMe: !blockedByMeQuery.empty,
      hasBlockedMe: !blockedMeQuery.empty,
      isBlocked: !blockedByMeQuery.empty || !blockedMeQuery.empty
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error checking block status', fallbackMessage: 'Failed to check block status' });
  }
};

module.exports = {
  blockUser,
  unblockUser,
  getBlockedUsers,
  checkIfBlocked
};