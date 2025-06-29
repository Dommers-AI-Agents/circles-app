// backend/controllers/firebaseUserController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createFriendRequest,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get user profile
// @route   GET /api/users/:id or /api/users/me
// @access  Private
exports.getUser = async (req, res, next) => {
  try {
    let userId = req.params.id === 'me' ? req.user.uid : req.params.id;
    
    // Parse the actual Firebase UID from complex format if needed
    if (userId && userId.includes('.')) {
      // Handle format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
      const parts = userId.split('.');
      if (parts.length >= 2) {
        userId = parts[1]; // Use the middle part as Firebase UID
        console.log(`🔐 getUser: Parsed Firebase UID: ${userId} from complex ID: ${req.params.id}`);
      }
    }
    
    console.log('🔍 DEBUG getUser:', {
      paramId: req.params.id,
      userUid: req.user.uid,
      userId: userId,
      userObject: req.user
    });
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is missing'
      });
    }
    
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);

    // If requesting another user's profile, limit returned data
    const isOwnProfile = userId === req.user.uid;
    
    const profileData = {
      _id: user.id,
      displayName: user.displayName,
      profilePicture: user.profilePicture,
      bio: user.bio,
      location: user.location,
      createdAt: user.createdAt
    };

    // Include private data only for own profile
    if (isOwnProfile) {
      profileData.email = user.email;
      profileData.friends = user.friends;
      profileData.friendRequests = user.friendRequests;
    }

    res.status(200).json({
      success: true,
      user: profileData
    });
  } catch (error) {
    console.error('Error fetching user:', error);
    next(error);
  }
};

// @desc    Update user profile
// @route   PUT /api/users/me
// @access  Private
exports.updateUser = async (req, res, next) => {
  try {
    const { displayName, bio, location, profilePicture } = req.body;
    
    const updateData = {
      updatedAt: new Date().toISOString()
    };

    if (displayName !== undefined) updateData.displayName = displayName;
    if (bio !== undefined) updateData.bio = bio;
    if (location !== undefined) updateData.location = location;
    if (profilePicture !== undefined) updateData.profilePicture = profilePicture;

    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    await userRef.update(updateData);

    // Get updated user
    const updatedUserDoc = await userRef.get();
    const user = serializeDoc(updatedUserDoc);

    res.status(200).json({
      success: true,
      user: {
        _id: user.id,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio,
        location: user.location,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('Error updating user:', error);
    next(error);
  }
};

// @desc    Search users
// @route   GET /api/users/search
// @access  Private
exports.searchUsers = async (req, res, next) => {
  try {
    const { q: query } = req.query;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    // Note: Firestore doesn't have full-text search built-in
    // For production, you'd want to use Algolia or similar
    // For now, we'll do a simple displayName search
    const snapshot = await db.collection(COLLECTIONS.USERS)
      .where('displayName', '>=', query)
      .where('displayName', '<=', query + '\uf8ff')
      .orderBy('displayName')
      .limit(20)
      .get();

    let users = serializeQuerySnapshot(snapshot);
    
    // Remove current user from results
    users = users.filter(user => user.id !== req.user.uid);

    // Return limited profile data
    const publicUsers = users.map(user => ({
      _id: user.id,
      displayName: user.displayName,
      profilePicture: user.profilePicture,
      bio: user.bio,
      location: user.location
    }));

    res.status(200).json({
      success: true,
      count: publicUsers.length,
      users: publicUsers
    });
  } catch (error) {
    console.error('Error searching users:', error);
    next(error);
  }
};

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
          _id: friend.id,
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

    // Parse the actual Firebase UID from complex format if needed
    if (userId && userId.includes('.')) {
      // Handle format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
      const parts = userId.split('.');
      if (parts.length >= 2) {
        userId = parts[1]; // Use the middle part as Firebase UID
        console.log(`🔐 sendFriendRequest: Parsed Firebase UID: ${userId} from complex ID: ${req.body.userId}`);
      }
    }

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
            _id: sender.id,
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

    // Parse the actual Firebase UID from complex format if needed
    if (friendId && friendId.includes('.')) {
      // Handle format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
      const parts = friendId.split('.');
      if (parts.length >= 2) {
        friendId = parts[1]; // Use the middle part as Firebase UID
        console.log(`🔐 removeFriend: Parsed Firebase UID: ${friendId} from complex ID: ${req.params.id}`);
      }
    }

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

// @desc    Search users by email, name, or phone
// @route   GET /api/users/search
// @access  Private
exports.searchUsers = async (req, res, next) => {
  try {
    const { query } = req.query;
    
    if (!query || query.trim().length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Search query must be at least 2 characters'
      });
    }

    const searchTerm = query.trim().toLowerCase();
    const currentUserId = req.user.uid;
    
    // Search users by email, name, or phone
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    
    const matchingUsers = [];
    for (const doc of usersSnapshot.docs) {
      const user = serializeDoc(doc);
      
      // Skip current user
      if (user.id === currentUserId) continue;
      
      // Check if query matches email, name, or phone
      const emailMatch = user.email && user.email.toLowerCase().includes(searchTerm);
      const nameMatch = user.displayName && user.displayName.toLowerCase().includes(searchTerm);
      const phoneMatch = user.phone && user.phone.replace(/\D/g, '').includes(searchTerm.replace(/\D/g, ''));
      
      if (emailMatch || nameMatch || phoneMatch) {
        // Check connection status
        const connectionQuery = await db.collection(COLLECTIONS.CONNECTIONS)
          .where('participants', 'array-contains', currentUserId)
          .get();
        
        let connectionStatus = 'none';
        for (const connDoc of connectionQuery.docs) {
          const conn = connDoc.data();
          if (conn.participants.includes(user.id)) {
            connectionStatus = conn.status;
            break;
          }
        }
        
        matchingUsers.push({
          _id: user.id,
          displayName: user.displayName,
          email: user.email,
          profilePicture: user.profilePicture,
          connectionStatus: connectionStatus
        });
      }
    }
    
    res.status(200).json({
      success: true,
      count: matchingUsers.length,
      users: matchingUsers
    });
  } catch (error) {
    console.error('Error searching users:', error);
    next(error);
  }
};

// @desc    Reorder user's circles
// @route   PUT /api/users/me/circles/reorder
// @access  Private
exports.reorderCircles = async (req, res, next) => {
  try {
    const { circleIds } = req.body;
    
    if (!circleIds || !Array.isArray(circleIds)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide an array of circle IDs'
      });
    }
    
    // Verify all circle IDs belong to the user
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', req.user.uid)
      .get();
    
    const userCircleIds = [];
    circlesSnapshot.forEach(doc => {
      userCircleIds.push(doc.id);
    });
    
    // Check if all provided IDs exist in user's circles
    const allIdsExist = circleIds.every(id => userCircleIds.includes(id));
    
    if (!allIdsExist) {
      return res.status(400).json({
        success: false,
        message: 'Invalid circle IDs - some circles do not belong to this user'
      });
    }
    
    // Update the user document with the new circle order
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    await userRef.update({
      circleOrder: circleIds,
      updatedAt: new Date().toISOString()
    });
    
    console.log('Updated circle order for user:', req.user.uid);
    console.log('New order:', circleIds);
    
    res.status(200).json({
      success: true,
      message: 'Circles reordered successfully'
    });
    
  } catch (error) {
    console.error('Error reordering circles:', error);
    next(error);
  }
};

// @desc    Register device token for push notifications
// @route   POST /api/users/device-token
// @access  Private
exports.registerDeviceToken = async (req, res, next) => {
  try {
    const { deviceToken, platform } = req.body;
    
    if (!deviceToken || !platform) {
      return res.status(400).json({
        success: false,
        message: 'Please provide device token and platform'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    const deviceTokens = userData.deviceTokens || [];
    
    // Check if this token already exists
    const existingTokenIndex = deviceTokens.findIndex(t => t.token === deviceToken);
    
    if (existingTokenIndex !== -1) {
      // Update existing token
      deviceTokens[existingTokenIndex] = {
        token: deviceToken,
        platform: platform,
        updatedAt: new Date().toISOString()
      };
    } else {
      // Add new token
      deviceTokens.push({
        token: deviceToken,
        platform: platform,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
    }
    
    await userRef.update({
      deviceTokens: deviceTokens,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Device token registered for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Device token registered successfully'
    });
  } catch (error) {
    console.error('Error registering device token:', error);
    next(error);
  }
};

// @desc    Remove device token
// @route   DELETE /api/users/device-token
// @access  Private
exports.removeDeviceToken = async (req, res, next) => {
  try {
    const { deviceToken } = req.body;
    
    if (!deviceToken) {
      return res.status(400).json({
        success: false,
        message: 'Please provide device token'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    const deviceTokens = userData.deviceTokens || [];
    
    // Remove the token
    const updatedTokens = deviceTokens.filter(t => t.token !== deviceToken);
    
    await userRef.update({
      deviceTokens: updatedTokens,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Device token removed for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Device token removed successfully'
    });
  } catch (error) {
    console.error('Error removing device token:', error);
    next(error);
  }
};

// @desc    Update notification preferences
// @route   PUT /api/users/notification-preferences
// @access  Private
exports.updateNotificationPreferences = async (req, res, next) => {
  try {
    const { notificationPreferences } = req.body;
    
    if (!notificationPreferences) {
      return res.status(400).json({
        success: false,
        message: 'Please provide notification preferences'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    await userRef.update({
      notificationPreferences: notificationPreferences,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Notification preferences updated for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Notification preferences updated successfully'
    });
  } catch (error) {
    console.error('Error updating notification preferences:', error);
    next(error);
  }
};