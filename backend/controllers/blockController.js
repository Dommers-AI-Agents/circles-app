const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Block a user
// @route   POST /api/blocks/user/:userId
// @access  Private
const blockUser = async (req, res) => {
  try {
    const blockerId = req.user.firebaseDocId || req.user.uid;
    const blockedUserId = req.params.userId;

    if (blockerId === blockedUserId) {
      return res.status(400).json({
        success: false,
        message: 'You cannot block yourself'
      });
    }

    // Check if user exists
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(blockedUserId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Check if block already exists
    const existingBlockQuery = await db.collection(COLLECTIONS.BLOCKS)
      .where('blockerId', '==', blockerId)
      .where('blockedUserId', '==', blockedUserId)
      .get();

    if (!existingBlockQuery.empty) {
      return res.status(400).json({
        success: false,
        message: 'User is already blocked'
      });
    }

    // Create block document
    const blockData = {
      blockerId,
      blockedUserId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const blockRef = await db.collection(COLLECTIONS.BLOCKS).add(blockData);
    const createdBlock = serializeDoc(await blockRef.get());

    // Also check if there's an existing connection and update its status
    const connectionQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', blockerId)
      .where('connectedUserId', '==', blockedUserId)
      .get();

    const connectionQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', blockedUserId)
      .where('connectedUserId', '==', blockerId)
      .get();

    const batch = db.batch();
    
    // Update any existing connections to blocked status
    [...connectionQuery1.docs, ...connectionQuery2.docs].forEach(doc => {
      batch.update(doc.ref, {
        status: 'blocked',
        blockedBy: blockerId,
        updatedAt: new Date().toISOString()
      });
    });

    await batch.commit();

    res.status(201).json({
      success: true,
      message: 'User blocked successfully',
      block: createdBlock
    });
  } catch (error) {
    console.error('Error blocking user:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to block user',
      error: error.message
    });
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

    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'User unblocked successfully'
    });
  } catch (error) {
    console.error('Error unblocking user:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to unblock user',
      error: error.message
    });
  }
};

// @desc    Get list of blocked users
// @route   GET /api/blocks
// @access  Private
const getBlockedUsers = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const { limit = 50, startAfter } = req.query;

    let query = db.collection(COLLECTIONS.BLOCKS)
      .where('blockerId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit));

    if (startAfter) {
      const startDoc = await db.collection(COLLECTIONS.BLOCKS).doc(startAfter).get();
      if (startDoc.exists) {
        query = query.startAfter(startDoc);
      }
    }

    const snapshot = await query.get();
    const blocks = [];

    // Get user details for each blocked user
    for (const doc of snapshot.docs) {
      const block = serializeDoc(doc);
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(block.blockedUserId).get();
      
      if (userDoc.exists) {
        block.blockedUser = serializeDoc(userDoc);
      }
      
      blocks.push(block);
    }

    res.status(200).json({
      success: true,
      blocks,
      hasMore: snapshot.docs.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error fetching blocked users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch blocked users',
      error: error.message
    });
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
    console.error('Error checking block status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check block status',
      error: error.message
    });
  }
};

module.exports = {
  blockUser,
  unblockUser,
  getBlockedUsers,
  checkIfBlocked
};