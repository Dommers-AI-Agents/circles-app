// backend/controllers/users/friendRequestController.js
// legacy friend-request endpoints (connections live in connectionController)
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, createFriendRequest, serializeDoc } = require('../../models/FirestoreModels');
const { normalizeUserId } = require('../../services/idService');

const db = getFirestore();

// @desc    Get user's friends
// @route   GET /api/users/me/friends
// @access  Private
exports.getFriends = async (req, res, next) => {
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const friendIds = user.friends || [];

    if (friendIds.length === 0) {
      return res.status(200).json({
        success: true,
        count: 0,
        users: []
      });
    }

    // Get friend profiles
    const friendProfiles = [];
    for (const friendId of friendIds) {
      const friendDoc = await db.collection(COLLECTIONS.USERS).doc(friendId).get();
      if (friendDoc.exists) {
        const friend = serializeDoc(friendDoc);
        friendProfiles.push({
          _id: normalizeUserId(friend.id), // Always return normalized ID
          displayName: friend.displayName,
          profilePicture: friend.profilePicture,
          bio: friend.bio,
          location: friend.location
        });
      }
    }

    res.status(200).json({
      success: true,
      count: friendProfiles.length,
      users: friendProfiles
    });
  } catch (error) {
    console.error('Error fetching friends:', error);
    next(error);
  }
};

// @desc    Send friend request
// @route   POST /api/users/friend-request
// @access  Private
exports.sendFriendRequest = async (req, res, next) => {
  try {
    let { userId } = req.body;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }

    // Normalize user ID
    userId = normalizeUserId(userId);
    console.log(`🔐 sendFriendRequest: Normalized user ID: ${userId} from ${req.body.userId}`);

    if (userId === req.user.uid) {
      return res.status(400).json({
        success: false,
        message: 'Cannot send friend request to yourself'
      });
    }

    // Check if target user exists
    const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Check if users are already friends
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    const currentUser = serializeDoc(currentUserDoc);
    
    if (currentUser.friends && currentUser.friends.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'Users are already friends'
      });
    }

    // Check if friend request already exists
    const existingRequestSnapshot = await db.collection(COLLECTIONS.FRIEND_REQUESTS)
      .where('from', '==', req.user.uid)
      .where('to', '==', userId)
      .where('status', '==', 'pending')
      .get();

    if (!existingRequestSnapshot.empty) {
      return res.status(400).json({
        success: false,
        message: 'Friend request already sent'
      });
    }

    // Create friend request
    const friendRequestData = createFriendRequest(req.user.uid, userId);
    await db.collection(COLLECTIONS.FRIEND_REQUESTS).add(friendRequestData);

    res.status(201).json({
      success: true,
      message: 'Friend request sent successfully'
    });
  } catch (error) {
    console.error('Error sending friend request:', error);
    next(error);
  }
};

// @desc    Get friend requests
// @route   GET /api/users/me/friend-requests
// @access  Private
exports.getFriendRequests = async (req, res, next) => {
  try {
    const snapshot = await db.collection(COLLECTIONS.FRIEND_REQUESTS)
      .where('to', '==', req.user.uid)
      .where('status', '==', 'pending')
      .orderBy('createdAt', 'desc')
      .get();

    const friendRequests = [];
    for (const doc of snapshot.docs) {
      const request = serializeDoc(doc);
      
      // Get sender profile
      const senderDoc = await db.collection(COLLECTIONS.USERS).doc(request.from).get();
      if (senderDoc.exists) {
        const sender = serializeDoc(senderDoc);
        friendRequests.push({
          id: request.id,
          from: {
            _id: normalizeUserId(sender.id), // Always return normalized ID
            displayName: sender.displayName,
            profilePicture: sender.profilePicture
          },
          createdAt: request.createdAt,
          status: request.status
        });
      }
    }

    res.status(200).json({
      success: true,
      count: friendRequests.length,
      friendRequests: friendRequests
    });
  } catch (error) {
    console.error('Error fetching friend requests:', error);
    next(error);
  }
};

// @desc    Accept/Reject friend request
// @route   POST /api/users/friend-request/:id/accept
// @route   POST /api/users/friend-request/:id/reject
// @access  Private
exports.respondToFriendRequest = async (req, res, next) => {
  try {
    const requestId = req.params.id;
    const action = req.path.includes('/accept') ? 'accepted' : 'rejected';

    const requestRef = db.collection(COLLECTIONS.FRIEND_REQUESTS).doc(requestId);
    const requestDoc = await requestRef.get();

    if (!requestDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Friend request not found'
      });
    }

    const friendRequest = serializeDoc(requestDoc);

    // Make sure this request is for the current user
    if (friendRequest.to !== req.user.uid) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to respond to this friend request'
      });
    }

    // Update request status
    await requestRef.update({
      status: action,
      updatedAt: new Date().toISOString()
    });

    // If accepted, add to friends lists
    if (action === 'accepted') {
      const batch = db.batch();

      // Add to current user's friends
      const currentUserRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
      const currentUserDoc = await currentUserRef.get();
      const currentUser = serializeDoc(currentUserDoc);
      const currentFriends = currentUser.friends || [];
      
      batch.update(currentUserRef, {
        friends: [...currentFriends, friendRequest.from],
        updatedAt: new Date().toISOString()
      });

      // Add to sender's friends
      const senderRef = db.collection(COLLECTIONS.USERS).doc(friendRequest.from);
      const senderDoc = await senderRef.get();
      const sender = serializeDoc(senderDoc);
      const senderFriends = sender.friends || [];
      
      batch.update(senderRef, {
        friends: [...senderFriends, req.user.uid],
        updatedAt: new Date().toISOString()
      });

      await batch.commit();
    }

    res.status(200).json({
      success: true,
      message: `Friend request ${action} successfully`
    });
  } catch (error) {
    console.error('Error responding to friend request:', error);
    next(error);
  }
};

// @desc    Remove friend
// @route   DELETE /api/users/friend/:id
// @access  Private
exports.removeFriend = async (req, res, next) => {
  try {
    let friendId = req.params.id;

    // Normalize friend ID
    friendId = normalizeUserId(friendId);
    console.log(`🔐 removeFriend: Normalized friend ID: ${friendId} from ${req.params.id}`);

    if (friendId === req.user.uid) {
      return res.status(400).json({
        success: false,
        message: 'Cannot remove yourself as friend'
      });
    }

    // Check if users are actually friends
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    const currentUser = serializeDoc(currentUserDoc);
    
    if (!currentUser.friends || !currentUser.friends.includes(friendId)) {
      return res.status(400).json({
        success: false,
        message: 'Users are not friends'
      });
    }

    const batch = db.batch();

    // Remove from current user's friends
    const currentUserRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const updatedCurrentFriends = currentUser.friends.filter(id => id !== friendId);
    batch.update(currentUserRef, {
      friends: updatedCurrentFriends,
      updatedAt: new Date().toISOString()
    });

    // Remove from friend's friends list
    const friendRef = db.collection(COLLECTIONS.USERS).doc(friendId);
    const friendDoc = await friendRef.get();
    if (friendDoc.exists) {
      const friend = serializeDoc(friendDoc);
      const updatedFriendFriends = (friend.friends || []).filter(id => id !== req.user.uid);
      batch.update(friendRef, {
        friends: updatedFriendFriends,
        updatedAt: new Date().toISOString()
      });
    }

    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'Friend removed successfully'
    });
  } catch (error) {
    console.error('Error removing friend:', error);
    next(error);
  }
};
