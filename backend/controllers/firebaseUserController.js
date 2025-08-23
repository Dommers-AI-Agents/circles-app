// backend/controllers/firebaseUserController.js
const { getFirestore, admin } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { 
  COLLECTIONS, 
  createFriendRequest,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { normalizeUserId, isSameUser } = require('../services/idService');

const db = getFirestore();

// @desc    Get user profile
// @route   GET /api/users/:id or /api/users/me
// @access  Private
exports.getUser = async (req, res, next) => {
  console.log('🚀 USER CONTROLLER: getUser called');
  console.log('🚀 USER CONTROLLER: Request params:', req.params);
  // User controller processing
  
  try {
    // Handle /me endpoint or when no ID is provided
    const isMe = req.params.id === 'me' || req.params.id === undefined;
    
    // Normalize user ID using centralized service
    let userId = isMe ? req.user.uid : normalizeUserId(req.params.id);
    
    console.log('🔍 USER CONTROLLER: DEBUG getUser:', {
      paramId: req.params.id,
      normalizedId: userId,
      userUid: req.user.uid,
      originalUid: req.user.originalUid,
      isMe: isMe
    });
    
    if (!userId) {
      console.log('❌ USER CONTROLLER: User ID is missing');
      return res.status(400).json({
        success: false,
        message: 'User ID is missing'
      });
    }
    
    // First try with the normalized ID
    console.log('🔐 USER CONTROLLER: Looking up user with ID:', userId);
    let userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    console.log('🔐 USER CONTROLLER: User doc exists with normalized ID?', userDoc.exists);
    
    // If not found and this is a 'me' request, try original UID
    if (!userDoc.exists && isMe && req.user.originalUid && req.user.originalUid !== userId) {
      console.log(`⚠️ USER CONTROLLER: User doc not found with normalized ID ${userId}, trying original ${req.user.originalUid}`);
      userDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.originalUid).get();
      console.log('🔐 USER CONTROLLER: User doc exists with original ID?', userDoc.exists);
    }
    
    // If still not found and we have an email, try that
    if (!userDoc.exists && isMe && req.user.email) {
      console.log(`⚠️ USER CONTROLLER: User doc not found by ID, trying email ${req.user.email}`);
      const usersWithEmail = await db.collection(COLLECTIONS.USERS)
        .where('email', '==', req.user.email)
        .limit(1)
        .get();
      
      if (!usersWithEmail.empty) {
        userDoc = usersWithEmail.docs[0];
        console.log(`✅ USER CONTROLLER: Found user by email, doc ID: ${userDoc.id}`);
      } else {
        console.log('❌ USER CONTROLLER: No user found with email:', req.user.email);
      }
    }
    
    if (!userDoc.exists) {
      console.error(`❌ USER CONTROLLER: User document not found. Tried IDs: ${userId}, ${req.user.originalUid}, email: ${req.user.email}`);
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);

    // If requesting another user's profile, limit returned data
    const isOwnProfile = userId === req.user.uid;
    
    const profileData = {
      _id: normalizeUserId(user.id), // Always return normalized ID
      displayName: user.displayName,
      profilePicture: user.profilePicture,
      bio: user.bio,
      location: user.location,
      createdAt: user.createdAt,
      followersCount: user.followersCount || 0,
      followingCount: user.followingCount || 0
    };

    // Include private data only for own profile
    if (isOwnProfile) {
      profileData.email = user.email;
      profileData.firstName = user.firstName || null;
      profileData.lastName = user.lastName || null;
      profileData.phoneNumber = user.phoneNumber || null;
      profileData.friends = user.friends;
      profileData.friendRequests = user.friendRequests;
      profileData.followers = user.followers;
      profileData.following = user.following;
      profileData.deviceTokens = user.deviceTokens; // Include device tokens for own profile
    } else {
      // For other users, check if current user is following them
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
      if (currentUserDoc.exists) {
        const currentUserData = currentUserDoc.data();
        const following = currentUserData.following || [];
        profileData.isFollowing = following.includes(userId);
      } else {
        profileData.isFollowing = false;
      }
      
      // Calculate mutual connections count
      try {
        // Get current user's connections
        const [currentUserConnections1, currentUserConnections2] = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', req.user.uid)
            .where('status', '==', 'accepted')
            .get(),
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('connectedUserId', '==', req.user.uid)
            .where('status', '==', 'accepted')
            .get()
        ]);
        
        // Get target user's connections
        const [targetUserConnections1, targetUserConnections2] = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', userId)
            .where('status', '==', 'accepted')
            .get(),
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('connectedUserId', '==', userId)
            .where('status', '==', 'accepted')
            .get()
        ]);
        
        // Extract connection IDs for current user
        const currentUserConnectionIds = new Set();
        currentUserConnections1.docs.forEach(doc => {
          currentUserConnectionIds.add(doc.data().connectedUserId);
        });
        currentUserConnections2.docs.forEach(doc => {
          currentUserConnectionIds.add(doc.data().userId);
        });
        
        // Extract connection IDs for target user
        const targetUserConnectionIds = new Set();
        targetUserConnections1.docs.forEach(doc => {
          targetUserConnectionIds.add(doc.data().connectedUserId);
        });
        targetUserConnections2.docs.forEach(doc => {
          targetUserConnectionIds.add(doc.data().userId);
        });
        
        // Find mutual connections (intersection of both sets)
        const mutualConnections = new Set(
          [...currentUserConnectionIds].filter(id => targetUserConnectionIds.has(id))
        );
        
        profileData.mutualConnectionsCount = mutualConnections.size;
        
        console.log(`👥 Mutual connections between ${req.user.uid} and ${userId}: ${mutualConnections.size}`);
      } catch (mutualError) {
        console.error('Error calculating mutual connections:', mutualError);
        profileData.mutualConnectionsCount = 0;
      }
    }

    console.log('✅ USER CONTROLLER: Sending user profile response');
    // Profile data prepared
    
    // Debug log for optional fields
    if (isOwnProfile) {
      console.log('🔍 USER CONTROLLER: Optional fields - firstName:', profileData.firstName, 'lastName:', profileData.lastName, 'phoneNumber:', profileData.phoneNumber);
    }
    
    res.status(200).json({
      success: true,
      user: profileData
    });
  } catch (error) {
    console.error('❌ USER CONTROLLER: Error fetching user:', error);
    console.error('❌ USER CONTROLLER: Error stack:', error.stack);
    next(error);
  }
};

// @desc    Update user profile
// @route   PUT /api/users/me
// @access  Private
exports.updateUser = async (req, res, next) => {
  try {
    const { displayName, firstName, lastName, phoneNumber, bio, location, profilePicture } = req.body;
    
    const updateData = {
      updatedAt: new Date().toISOString()
    };

    if (displayName !== undefined) {
      updateData.displayName = displayName;
      // Add lowercase version for search
      updateData.displayNameLowercase = displayName.toLowerCase();
    }
    if (firstName !== undefined) updateData.firstName = firstName;
    if (lastName !== undefined) updateData.lastName = lastName;
    if (phoneNumber !== undefined) updateData.phoneNumber = phoneNumber;
    if (bio !== undefined) updateData.bio = bio;
    if (location !== undefined) updateData.location = location;
    if (profilePicture !== undefined) {
      updateData.profilePicture = profilePicture;
      // Mark that user has uploaded a custom profile picture
      if (profilePicture && profilePicture.includes('firebasestorage.googleapis.com')) {
        updateData.hasCustomProfilePicture = true;
        console.log('🖼️ Setting hasCustomProfilePicture flag to true for custom uploaded image');
      }
    }

    console.log('🔄 Updating user profile:', {
      userId: req.user.uid,
      originalUid: req.user.originalUid,
      userEmail: req.user.email,
      updateFields: Object.keys(updateData),
      hasProfilePicture: !!profilePicture,
      profilePictureLength: profilePicture ? profilePicture.length : 0
    });

    // First check if the document exists with the normalized ID
    let userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    let userDoc = await userRef.get();
    
    // If not found with normalized ID and we have an original UID, try that
    if (!userDoc.exists && req.user.originalUid && req.user.originalUid !== req.user.uid) {
      console.log(`⚠️ User doc not found with normalized ID ${req.user.uid}, trying original ${req.user.originalUid}`);
      userRef = db.collection(COLLECTIONS.USERS).doc(req.user.originalUid);
      userDoc = await userRef.get();
    }
    
    // If still not found, try to find by email
    if (!userDoc.exists && req.user.email) {
      console.log(`⚠️ User doc not found by ID, trying email ${req.user.email}`);
      const usersWithEmail = await db.collection(COLLECTIONS.USERS)
        .where('email', '==', req.user.email)
        .limit(1)
        .get();
      
      if (!usersWithEmail.empty) {
        userDoc = usersWithEmail.docs[0];
        userRef = userDoc.ref;
        console.log(`✅ Found user by email, doc ID: ${userDoc.id}`);
      }
    }
    
    if (!userDoc.exists) {
      console.error(`❌ User document not found for update. Tried IDs: ${req.user.uid}, ${req.user.originalUid}, email: ${req.user.email}`);
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    await userRef.update(updateData);
    console.log(`✅ User profile updated successfully for doc ID: ${userDoc.id}`);
    
    // Log profile picture update specifically
    if (updateData.profilePicture) {
      console.log('📸 Profile picture updated:', {
        userId: userDoc.id,
        userEmail: req.user.email,
        profilePictureUrl: updateData.profilePicture.substring(0, 100) + '...'
      });
    }

    // Get updated user
    const updatedUserDoc = await userRef.get();
    const user = serializeDoc(updatedUserDoc);

    res.status(200).json({
      success: true,
      user: {
        _id: user.id,
        email: user.email,
        displayName: user.displayName,
        firstName: user.firstName,
        lastName: user.lastName,
        phoneNumber: user.phoneNumber,
        profilePicture: user.profilePicture,
        bio: user.bio,
        location: user.location,
        followersCount: user.followersCount || 0,
        followingCount: user.followingCount || 0,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('❌ Error updating user profile:', error);
    console.error('Error details:', {
      errorMessage: error.message,
      errorCode: error.code,
      userId: req.user?.uid,
      userEmail: req.user?.email,
      updateFields: Object.keys(updateData || {})
    });
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

// @desc    Search users by email, name, or phone
// @route   GET /api/users/search
// @access  Private
exports.searchUsers = async (req, res, next) => {
  try {
    const { query } = req.query;
    const currentUserId = req.user.uid; // Already normalized by middleware
    
    console.log(`🔍 searchUsers - currentUserId: ${currentUserId}, query: '${query}'`);
    
    // If no query provided, return all users sorted alphabetically
    if (!query || query.trim().length === 0) {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      const allUsers = [];
      console.log(`Found ${usersSnapshot.size} total users in database`);
      
      // Get all connections for current user
      const connectionQueries = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).get(),
        db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', currentUserId).get()
      ]);
      
      const allConnections = new Set();
      connectionQueries.forEach(query => {
        query.docs.forEach(doc => allConnections.add(doc.id));
      });
      
      console.log(`Current user ${currentUserId} has ${allConnections.size} total connections`);
      
      // Log a sample connection for debugging
      if (allConnections.size > 0) {
        const firstConnDoc = connectionQueries.find(q => q.size > 0)?.docs[0];
        if (firstConnDoc) {
          console.log('Sample connection:', firstConnDoc.data());
        }
      }
      
      // Get current user's following list to check isFollowing for each user
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      const currentUserData = currentUserDoc.exists ? currentUserDoc.data() : {};
      const following = currentUserData.following || [];
      
      for (const doc of usersSnapshot.docs) {
        const user = serializeDoc(doc);
        
        // Skip current user - use isSameUser to handle all ID formats
        if (isSameUser(user.id, currentUserId)) {
          console.log(`Skipping current user: ${user.id}`);
          continue;
        }
        
        
        // Check connection status using normalized IDs
        const targetUserId = normalizeUserId(user.id);
        
        // Check both directions for connection
        const connectionChecks = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).where('connectedUserId', '==', targetUserId).get(),
          db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', targetUserId).where('connectedUserId', '==', currentUserId).get()
        ]);
        
        let connectionStatus = 'none';
        let connectionDirection = null; // 'incoming' or 'outgoing' for pending requests
        let connectionId = null;
        
        for (let i = 0; i < connectionChecks.length; i++) {
          const query = connectionChecks[i];
          if (!query.empty) {
            const connectionData = query.docs[0].data();
            connectionStatus = connectionData.status;
            connectionId = query.docs[0].id;
            
            // Determine direction for pending connections
            if (connectionStatus === 'pending') {
              // i === 0: current user is userId (outgoing request)
              // i === 1: current user is connectedUserId (incoming request)
              connectionDirection = i === 0 ? 'outgoing' : 'incoming';
            }
            break;
          }
        }
        
        // Check if current user is following this user
        const isFollowing = following.includes(targetUserId);
        
        allUsers.push({
          _id: normalizeUserId(user.id), // Always return normalized ID
          displayName: user.displayName,
          firstName: user.firstName,
          lastName: user.lastName,
          email: user.email,
          profilePicture: user.profilePicture,
          bio: user.bio,
          location: user.location,
          connectionStatus: connectionStatus,
          connectionDirection: connectionDirection,
          connectionId: connectionId,
          isFollowing: isFollowing
        });
      }
      
      // Sort alphabetically by display name
      allUsers.sort((a, b) => {
        const nameA = a.displayName || '';
        const nameB = b.displayName || '';
        return nameA.localeCompare(nameB);
      });
      
      return res.status(200).json({
        success: true,
        count: allUsers.length,
        users: allUsers
      });
    }

    const searchTerm = query.trim().toLowerCase();
    
    // Search users by email, name, or phone
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    
    // Normalize the current user ID for consistent comparisons
    const simpleUserId = normalizeUserId(currentUserId);
    
    // Get current user's following list to check isFollowing for each user
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
    const currentUserData = currentUserDoc.exists ? currentUserDoc.data() : {};
    const following = currentUserData.following || [];
    
    const matchingUsers = [];
    for (const doc of usersSnapshot.docs) {
      const user = serializeDoc(doc);
      
      // Skip current user - check both complex and simple ID formats
      if (user.id === currentUserId || user.id === simpleUserId) continue;
      
      // Also check if the complex ID contains the simple ID
      if (user.id && user.id.includes('.') && simpleUserId) {
        const parts = user.id.split('.');
        if (parts.length >= 2 && parts[1] === simpleUserId) continue;
      }
      
      // Also check the reverse - if current user has complex ID and we're comparing with simple ID
      if (currentUserId && currentUserId.includes('.')) {
        const currentUserParts = currentUserId.split('.');
        if (currentUserParts.length >= 2 && user.id === currentUserParts[1]) continue;
      }
      
      // Check if query matches email, name, or phone (using startsWith for better UX)
      const emailMatch = user.email && user.email.toLowerCase().startsWith(searchTerm);
      const displayNameMatch = user.displayName && user.displayName.toLowerCase().startsWith(searchTerm);
      const firstNameMatch = user.firstName && user.firstName.toLowerCase().startsWith(searchTerm);
      const lastNameMatch = user.lastName && user.lastName.toLowerCase().startsWith(searchTerm);
      const phoneMatch = user.phoneNumber && user.phoneNumber.replace(/\D/g, '').startsWith(searchTerm.replace(/\D/g, ''));
      
      // Also check if any word in display name starts with search term
      const displayNameWords = user.displayName ? user.displayName.toLowerCase().split(' ') : [];
      const wordMatch = displayNameWords.some(word => word.startsWith(searchTerm));
      
      if (emailMatch || displayNameMatch || firstNameMatch || lastNameMatch || phoneMatch || wordMatch) {
        // Check connection status using normalized IDs
        const targetUserId = normalizeUserId(user.id);
        
        // Check both directions for connection
        const connectionChecks = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).where('connectedUserId', '==', targetUserId).get(),
          db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', targetUserId).where('connectedUserId', '==', currentUserId).get()
        ]);
        
        let connectionStatus = 'none';
        let connectionDirection = null; // 'incoming' or 'outgoing' for pending requests
        let connectionId = null;
        
        for (let i = 0; i < connectionChecks.length; i++) {
          const query = connectionChecks[i];
          if (!query.empty) {
            const connectionData = query.docs[0].data();
            connectionStatus = connectionData.status;
            connectionId = query.docs[0].id;
            
            // Determine direction for pending connections
            if (connectionStatus === 'pending') {
              // i === 0: current user is userId (outgoing request)
              // i === 1: current user is connectedUserId (incoming request)
              connectionDirection = i === 0 ? 'outgoing' : 'incoming';
            }
            break;
          }
        }
        
        // Check if current user is following this user
        const isFollowing = following.includes(targetUserId);
        
        matchingUsers.push({
          _id: normalizeUserId(user.id), // Always return normalized ID
          displayName: user.displayName,
          firstName: user.firstName,
          lastName: user.lastName,
          email: user.email,
          profilePicture: user.profilePicture,
          bio: user.bio,
          location: user.location,
          connectionStatus: connectionStatus,
          connectionDirection: connectionDirection,
          connectionId: connectionId,
          isFollowing: isFollowing
        });
      }
    }
    
    // Sort results by relevance (exact matches first, then partial matches)
    matchingUsers.sort((a, b) => {
      // Prioritize exact email matches
      const aExact = a.email?.toLowerCase() === searchTerm;
      const bExact = b.email?.toLowerCase() === searchTerm;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;
      
      // Then prioritize display name matches
      const aNameExact = a.displayName?.toLowerCase() === searchTerm;
      const bNameExact = b.displayName?.toLowerCase() === searchTerm;
      if (aNameExact && !bNameExact) return -1;
      if (!aNameExact && bNameExact) return 1;
      
      // Finally sort alphabetically
      return (a.displayName || '').localeCompare(b.displayName || '');
    });
    
    // Limit results to prevent overwhelming the UI
    const limitedUsers = matchingUsers.slice(0, 20);
    
    res.status(200).json({
      success: true,
      count: limitedUsers.length,
      users: limitedUsers
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
    const { deviceToken, platform, replaceExisting } = req.body;
    
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
    let deviceTokens = userData.deviceTokens || [];
    
    // If replaceExisting is true, clear all existing tokens for this platform
    if (replaceExisting) {
      console.log(`🔔 Replacing all existing ${platform} tokens for user ${req.user.uid}`);
      deviceTokens = deviceTokens.filter(t => t.platform !== platform);
    }
    
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

// @desc    Get user's public circles
// @route   GET /api/users/:id/circles
// @access  Private
exports.getUserPublicCircles = async (req, res, next) => {
  try {
    const targetUserId = req.params.id;
    const currentUserId = req.user.uid;
    
    // Check if users are connected
    const connectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', currentUserId)
      .where('connectedUserId', '==', targetUserId)
      .where('status', '==', 'accepted')
      .limit(1)
      .get();
    
    const reverseConnectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', targetUserId)
      .where('connectedUserId', '==', currentUserId)
      .where('status', '==', 'accepted')
      .limit(1)
      .get();
    
    const isConnected = !connectionSnapshot.empty || !reverseConnectionSnapshot.empty;
    
    // Build query based on connection status
    let circlesQuery = db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', targetUserId);
    
    // If not connected, only show public circles
    if (!isConnected && currentUserId !== targetUserId) {
      circlesQuery = circlesQuery.where('privacy', '==', 'public');
    } else if (isConnected) {
      // If connected, show public and myNetwork circles
      circlesQuery = circlesQuery.where('privacy', 'in', ['public', 'myNetwork']);
    }
    // If viewing own circles, show all
    
    const circlesSnapshot = await circlesQuery.get();
    const circles = serializeQuerySnapshot(circlesSnapshot);
    
    res.status(200).json({
      success: true,
      count: circles.length,
      circles: circles
    });
  } catch (error) {
    console.error('Error fetching user public circles:', error);
    next(error);
  }
};

// @desc    Follow a user
// @route   POST /api/users/:id/follow
// @access  Private
exports.followUser = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔵 followUser called:', {
      targetUserIdOriginal: req.params.id,
      targetUserIdNormalized: targetUserId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId,
      timestamp: new Date().toISOString()
    });
    
    // Can't follow yourself
    if (targetUserId === currentUserId) {
      return res.status(400).json({
        success: false,
        message: 'You cannot follow yourself'
      });
    }
    
    // Check if target user exists
    const targetUserRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const targetUserDoc = await targetUserRef.get();
    
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    // Get current user - fetch fresh to ensure we have latest data
    const currentUserRef = db.collection(COLLECTIONS.USERS).doc(currentUserId);
    let currentUserDoc = await currentUserRef.get();
    
    if (!currentUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Current user not found'
      });
    }
    
    // Double-check by fetching again to ensure we have the absolute latest data
    // This helps avoid race conditions from rapid follow/unfollow actions
    await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
    currentUserDoc = await currentUserRef.get();
    
    const currentUser = serializeDoc(currentUserDoc);
    const targetUser = serializeDoc(targetUserDoc);
    
    console.log('🔍 Current user following array BEFORE:', {
      userId: currentUserId,
      following: currentUser.following || [],
      followingCount: currentUser.followingCount || 0,
      followingLength: (currentUser.following || []).length,
      targetInArray: currentUser.following?.includes(targetUserId) || false,
      rawFollowingData: JSON.stringify(currentUser.following || [])
    });
    
    console.log('🔍 Target user followers array BEFORE:', {
      userId: targetUserId,
      followers: targetUser.followers || [],
      followersCount: targetUser.followersCount || 0,
      followersLength: (targetUser.followers || []).length,
      currentUserInArray: targetUser.followers?.includes(currentUserId) || false,
      rawFollowersData: JSON.stringify(targetUser.followers || [])
    });
    
    // Check if already following
    if (currentUser.following && currentUser.following.includes(targetUserId)) {
      console.log('⚠️ User already following target:', {
        currentUserId,
        targetUserId,
        followingArray: currentUser.following
      });
      return res.status(400).json({
        success: false,
        message: 'You are already following this user'
      });
    }
    
    // Initialize counts if they don't exist
    if (typeof currentUser.followingCount !== 'number') {
      console.log('⚠️ Initializing missing followingCount for user:', currentUserId);
      await currentUserRef.update({
        followingCount: (currentUser.following || []).length
      });
    }
    
    if (typeof targetUser.followersCount !== 'number') {
      console.log('⚠️ Initializing missing followersCount for user:', targetUserId);
      await targetUserRef.update({
        followersCount: (targetUser.followers || []).length
      });
    }
    
    // Update both users atomically with rollback capability
    const batch = db.batch();
    
    // Update current user's following list atomically
    batch.update(currentUserRef, {
      following: FieldValue.arrayUnion(targetUserId),
      followingCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    
    // Update target user's followers list atomically
    batch.update(targetUserRef, {
      followers: FieldValue.arrayUnion(currentUserId),
      followersCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    
    try {
      await batch.commit();
      console.log('✅ Follow batch committed successfully');
    } catch (batchError) {
      console.error('❌ Follow batch failed, attempting rollback:', batchError);
      
      // Attempt rollback by reversing the operations
      try {
        const rollbackBatch = db.batch();
        
        // Remove the user from following if they were added
        rollbackBatch.update(currentUserRef, {
          following: FieldValue.arrayRemove(targetUserId),
          followingCount: FieldValue.increment(-1),
          updatedAt: new Date().toISOString()
        });
        
        // Remove the follower if they were added
        rollbackBatch.update(targetUserRef, {
          followers: FieldValue.arrayRemove(currentUserId),
          followersCount: FieldValue.increment(-1),
          updatedAt: new Date().toISOString()
        });
        
        await rollbackBatch.commit();
        console.log('✅ Follow rollback completed successfully');
      } catch (rollbackError) {
        console.error('❌ Follow rollback failed:', rollbackError);
        // Even rollback failed, log for manual intervention
        console.error('🚨 CRITICAL: Follow operation and rollback both failed for users:', {
          currentUserId,
          targetUserId,
          originalError: batchError.message,
          rollbackError: rollbackError.message,
          timestamp: new Date().toISOString()
        });
      }
      
      // Return error to client
      return res.status(500).json({
        success: false,
        message: 'Failed to follow user. Please try again.'
      });
    }
    
    // Get updated counts for SSE events
    const updatedCurrentUser = await currentUserRef.get();
    const updatedTargetUser = await targetUserRef.get();
    const currentUserData = serializeDoc(updatedCurrentUser);
    const targetUserData = serializeDoc(updatedTargetUser);
    
    // Validate array/count consistency after follow operation
    const followingArrayLength = (currentUserData.following || []).length;
    const followingCount = currentUserData.followingCount || 0;
    const followersArrayLength = (targetUserData.followers || []).length;
    const followersCount = targetUserData.followersCount || 0;
    
    console.log('🔍 Post-follow validation:', {
      currentUser: {
        id: currentUserId,
        followingArrayLength,
        followingCount,
        consistent: followingArrayLength === followingCount
      },
      targetUser: {
        id: targetUserId,
        followersArrayLength,
        followersCount,
        consistent: followersArrayLength === followersCount
      }
    });
    
    // Check for inconsistencies and repair if needed
    const followingInconsistent = followingArrayLength !== followingCount;
    const followersInconsistent = followersArrayLength !== followersCount;
    
    if (followingInconsistent || followersInconsistent) {
      console.error('❌ Follow operation resulted in inconsistent data:', {
        followingInconsistent,
        followersInconsistent,
        currentUserId,
        targetUserId
      });
      
      // Attempt to repair the inconsistency
      const repairBatch = db.batch();
      
      if (followingInconsistent) {
        console.log('🔧 Repairing following count for user:', currentUserId);
        repairBatch.update(currentUserRef, {
          followingCount: followingArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      if (followersInconsistent) {
        console.log('🔧 Repairing followers count for user:', targetUserId);
        repairBatch.update(targetUserRef, {
          followersCount: followersArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      await repairBatch.commit();
      console.log('✅ Inconsistency repair completed');
      
      // Re-fetch the corrected data
      const correctedCurrentUser = await currentUserRef.get();
      const correctedTargetUser = await targetUserRef.get();
      const correctedCurrentUserData = serializeDoc(correctedCurrentUser);
      const correctedTargetUserData = serializeDoc(correctedTargetUser);
      
      // Use corrected data for SSE events
      currentUserData.followingCount = correctedCurrentUserData.followingCount;
      targetUserData.followersCount = correctedTargetUserData.followersCount;
    }
    
    console.log('📊 After follow - Updated data:', {
      currentUser: {
        id: currentUserId,
        following: currentUserData.following || [],
        followingCount: currentUserData.followingCount || 0,
        followingLength: (currentUserData.following || []).length,
        targetNowInArray: currentUserData.following?.includes(targetUserId) || false,
        rawFollowingData: JSON.stringify(currentUserData.following || [])
      },
      targetUser: {
        id: targetUserId,
        followers: targetUserData.followers || [],
        followersCount: targetUserData.followersCount || 0,
        followersLength: (targetUserData.followers || []).length,
        currentUserNowInArray: targetUserData.followers?.includes(currentUserId) || false,
        rawFollowersData: JSON.stringify(targetUserData.followers || [])
      }
    });
    
    // Send notification to target user
    const notificationService = require('../services/notificationService');
    await notificationService.sendFollowerNotification(
      targetUserId,
      currentUserId,
      currentUser.displayName
    );
    
    // Send SSE events to both users
    const sseService = require('../services/sseService');
    
    // Notify current user about their new following
    sseService.notifyUser(currentUserId, 'following_added', {
      followingCount: currentUserData.followingCount || 0,
      following: currentUserData.following || [],
      targetUserId: targetUserId
    });
    
    // Notify target user about their new follower
    sseService.notifyUser(targetUserId, 'follower_added', {
      followersCount: targetUserData.followersCount || 0,
      followers: targetUserData.followers || [],
      followerId: currentUserId
    });
    
    // Return updated target user data including isFollowing status
    const responseUserData = {
      _id: targetUserId,
      email: targetUserData.email || '', // Include email field for iOS decoding with fallback
      displayName: targetUserData.displayName,
      profilePicture: targetUserData.profilePicture,
      bio: targetUserData.bio,
      location: targetUserData.location,
      createdAt: targetUserData.createdAt,
      followersCount: targetUserData.followersCount || 0,
      followingCount: targetUserData.followingCount || 0,
      isFollowing: true // Current user is now following this user
    };

    res.status(200).json({
      success: true,
      message: 'Successfully followed user',
      user: responseUserData
    });
    
  } catch (error) {
    console.error('Error following user:', error);
    next(error);
  }
};

// @desc    Unfollow a user
// @route   POST /api/users/:id/unfollow
// @access  Private
exports.unfollowUser = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔴 unfollowUser called:', {
      targetUserIdOriginal: req.params.id,
      targetUserIdNormalized: targetUserId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId,
      timestamp: new Date().toISOString()
    });
    
    // Can't unfollow yourself
    if (targetUserId === currentUserId) {
      return res.status(400).json({
        success: false,
        message: 'You cannot unfollow yourself'
      });
    }
    
    // Get current user - fetch fresh to ensure we have latest data
    const currentUserRef = db.collection(COLLECTIONS.USERS).doc(currentUserId);
    let currentUserDoc = await currentUserRef.get();
    
    if (!currentUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Current user not found'
      });
    }
    
    // Double-check by fetching again to ensure we have the absolute latest data
    // This helps avoid race conditions from rapid follow/unfollow actions
    await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
    currentUserDoc = await currentUserRef.get();
    
    // Get target user
    const targetUserRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const targetUserDoc = await targetUserRef.get();
    
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const currentUser = serializeDoc(currentUserDoc);
    const targetUser = serializeDoc(targetUserDoc);
    
    console.log('🔍 Current user following array before unfollow:', {
      userId: currentUserId,
      following: currentUser.following || [],
      followingCount: currentUser.followingCount || 0,
      targetInArray: currentUser.following?.includes(targetUserId) || false
    });
    
    // Check if following
    if (!currentUser.following || !currentUser.following.includes(targetUserId)) {
      console.log('⚠️ User not following target:', {
        currentUserId,
        targetUserId,
        followingArray: currentUser.following || []
      });
      return res.status(400).json({
        success: false,
        message: 'You are not following this user'
      });
    }
    
    // Update both users atomically with rollback capability
    const batch = db.batch();
    
    // Update current user's following list atomically
    batch.update(currentUserRef, {
      following: FieldValue.arrayRemove(targetUserId),
      followingCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    // Update target user's followers list atomically
    batch.update(targetUserRef, {
      followers: FieldValue.arrayRemove(currentUserId),
      followersCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    try {
      await batch.commit();
      console.log('✅ Unfollow batch committed successfully');
    } catch (batchError) {
      console.error('❌ Unfollow batch failed, attempting rollback:', batchError);
      
      // Attempt rollback by reversing the operations
      try {
        const rollbackBatch = db.batch();
        
        // Re-add the user to following if they were removed
        rollbackBatch.update(currentUserRef, {
          following: FieldValue.arrayUnion(targetUserId),
          followingCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        // Re-add the follower if they were removed
        rollbackBatch.update(targetUserRef, {
          followers: FieldValue.arrayUnion(currentUserId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        await rollbackBatch.commit();
        console.log('✅ Unfollow rollback completed successfully');
      } catch (rollbackError) {
        console.error('❌ Unfollow rollback failed:', rollbackError);
        // Even rollback failed, log for manual intervention
        console.error('🚨 CRITICAL: Unfollow operation and rollback both failed for users:', {
          currentUserId,
          targetUserId,
          originalError: batchError.message,
          rollbackError: rollbackError.message,
          timestamp: new Date().toISOString()
        });
      }
      
      // Return error to client
      return res.status(500).json({
        success: false,
        message: 'Failed to unfollow user. Please try again.'
      });
    }
    
    // Get updated data for SSE events
    const updatedCurrentUser = await currentUserRef.get();
    const updatedTargetUser = await targetUserRef.get();
    const currentUserData = serializeDoc(updatedCurrentUser);
    const targetUserData = serializeDoc(updatedTargetUser);
    
    // Validate array/count consistency after unfollow operation
    const followingArrayLength = (currentUserData.following || []).length;
    const followingCount = currentUserData.followingCount || 0;
    const followersArrayLength = (targetUserData.followers || []).length;
    const followersCount = targetUserData.followersCount || 0;
    
    console.log('🔍 Post-unfollow validation:', {
      currentUser: {
        id: currentUserId,
        followingArrayLength,
        followingCount,
        consistent: followingArrayLength === followingCount
      },
      targetUser: {
        id: targetUserId,
        followersArrayLength,
        followersCount,
        consistent: followersArrayLength === followersCount
      }
    });
    
    // Check for inconsistencies and repair if needed
    const followingInconsistent = followingArrayLength !== followingCount;
    const followersInconsistent = followersArrayLength !== followersCount;
    
    if (followingInconsistent || followersInconsistent) {
      console.error('❌ Unfollow operation resulted in inconsistent data:', {
        followingInconsistent,
        followersInconsistent,
        currentUserId,
        targetUserId
      });
      
      // Attempt to repair the inconsistency
      const repairBatch = db.batch();
      
      if (followingInconsistent) {
        console.log('🔧 Repairing following count for user:', currentUserId);
        repairBatch.update(currentUserRef, {
          followingCount: followingArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      if (followersInconsistent) {
        console.log('🔧 Repairing followers count for user:', targetUserId);
        repairBatch.update(targetUserRef, {
          followersCount: followersArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      await repairBatch.commit();
      console.log('✅ Inconsistency repair completed');
      
      // Re-fetch the corrected data
      const correctedCurrentUser = await currentUserRef.get();
      const correctedTargetUser = await targetUserRef.get();
      const correctedCurrentUserData = serializeDoc(correctedCurrentUser);
      const correctedTargetUserData = serializeDoc(correctedTargetUser);
      
      // Use corrected data for SSE events
      currentUserData.followingCount = correctedCurrentUserData.followingCount;
      targetUserData.followersCount = correctedTargetUserData.followersCount;
    }
    
    console.log('📊 After unfollow - Updated data:', {
      currentUser: {
        id: currentUserId,
        following: currentUserData.following || [],
        followingCount: currentUserData.followingCount || 0,
        targetStillInArray: currentUserData.following?.includes(targetUserId) || false
      },
      targetUser: {
        id: targetUserId,
        followers: targetUserData.followers || [],
        followersCount: targetUserData.followersCount || 0,
        currentUserStillInArray: targetUserData.followers?.includes(currentUserId) || false
      }
    });
    
    // Send SSE events to both users
    const sseService = require('../services/sseService');
    
    // Notify current user about removing following
    sseService.notifyUser(currentUserId, 'following_removed', {
      followingCount: currentUserData.followingCount || 0,
      following: currentUserData.following || [],
      targetUserId: targetUserId
    });
    
    // Notify target user about losing follower
    sseService.notifyUser(targetUserId, 'follower_removed', {
      followersCount: targetUserData.followersCount || 0,
      followers: targetUserData.followers || [],
      followerId: currentUserId
    });
    
    // Return updated target user data including isFollowing status
    const responseUserData = {
      _id: targetUserId,
      email: targetUserData.email || '', // Include email field for iOS decoding with fallback
      displayName: targetUserData.displayName,
      profilePicture: targetUserData.profilePicture,
      bio: targetUserData.bio,
      location: targetUserData.location,
      createdAt: targetUserData.createdAt,
      followersCount: targetUserData.followersCount || 0,
      followingCount: targetUserData.followingCount || 0,
      isFollowing: false // Current user is no longer following this user
    };

    res.status(200).json({
      success: true,
      message: 'Successfully unfollowed user',
      user: responseUserData
    });
    
  } catch (error) {
    console.error('Error unfollowing user:', error);
    next(error);
  }
};

// @desc    Get user's followers (owner only)
// @route   GET /api/users/:id/followers
// @access  Private
exports.getUserFollowers = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('👥 getUserFollowers called:', {
      userIdOriginal: req.params.id,
      userIdNormalized: userId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId
    });
    
    // Allow any authenticated user to view followers lists
    // This enables social discovery through connections' networks
    
    // Get user
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const user = serializeDoc(userDoc);
    const followerIds = user.followers || [];
    
    // Get current user's following list to determine isFollowing status
    let currentUserFollowing = [];
    if (currentUserId !== userId) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      if (currentUserDoc.exists) {
        const currentUserData = serializeDoc(currentUserDoc);
        currentUserFollowing = (currentUserData.following || []).map(id => normalizeUserId(id));
      }
    } else {
      // If viewing own followers, use the profile owner's following list
      currentUserFollowing = (user.following || []).map(id => normalizeUserId(id));
    }
    
    // Get follower details with batch fetching for performance
    const followers = [];
    
    if (followerIds.length > 0) {
      // Normalize all follower IDs
      const normalizedFollowerIds = followerIds.map(id => normalizeUserId(id));
      
      // Batch fetch all followers in chunks of 10 (Firestore limit for 'in' queries)
      const chunkSize = 10;
      for (let i = 0; i < normalizedFollowerIds.length; i += chunkSize) {
        const chunk = normalizedFollowerIds.slice(i, i + chunkSize);
        
        const followersSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', chunk)
          .get();
        
        followersSnapshot.forEach(doc => {
          const follower = serializeDoc(doc);
          // Check if current user is following this follower
          const normalizedFollowerId = normalizeUserId(follower.id);
          const isFollowing = currentUserFollowing.includes(normalizedFollowerId);
          
          followers.push({
            id: normalizeUserId(follower.id), // Always return normalized ID
            email: follower.email || '', // Include email field for iOS decoding
            displayName: follower.displayName,
            profilePicture: follower.profilePicture || null,
            bio: follower.bio || null,
            firstName: follower.firstName || null,
            lastName: follower.lastName || null,
            isFollowing: isFollowing
          });
        });
      }
      
      // Log any missing followers
      const foundIds = followers.map(f => f.id);
      const missingIds = normalizedFollowerIds.filter(id => !foundIds.includes(id));
      if (missingIds.length > 0) {
        console.warn('⚠️ Followers not found:', missingIds);
      }
    }
    
    res.status(200).json({
      success: true,
      count: followers.length,
      followers: followers
    });
    
  } catch (error) {
    console.error('Error fetching followers:', error);
    next(error);
  }
};

// @desc    Get user's following (owner only)
// @route   GET /api/users/:id/following
// @access  Private
exports.getUserFollowing = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('👥 getUserFollowing called:', {
      userIdOriginal: req.params.id,
      userIdNormalized: userId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId
    });
    
    // Allow any authenticated user to view following lists
    // This enables social discovery through connections' networks
    
    // Get user
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const user = serializeDoc(userDoc);
    const followingIds = user.following || [];
    
    // Get current user's following list to determine isFollowing status
    let currentUserFollowing = [];
    if (currentUserId !== userId) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      if (currentUserDoc.exists) {
        const currentUserData = serializeDoc(currentUserDoc);
        currentUserFollowing = (currentUserData.following || []).map(id => normalizeUserId(id));
      }
    } else {
      // If viewing own following list, all users are followed by definition
      currentUserFollowing = followingIds.map(id => normalizeUserId(id));
    }
    
    // Get following details with batch fetching for performance
    const following = [];
    
    if (followingIds.length > 0) {
      // Normalize all following IDs
      const normalizedFollowingIds = followingIds.map(id => normalizeUserId(id));
      
      // Batch fetch all following users in chunks of 10 (Firestore limit for 'in' queries)
      const chunkSize = 10;
      for (let i = 0; i < normalizedFollowingIds.length; i += chunkSize) {
        const chunk = normalizedFollowingIds.slice(i, i + chunkSize);
        
        const followingSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', chunk)
          .get();
        
        followingSnapshot.forEach(doc => {
          const followingUser = serializeDoc(doc);
          // Check if current user is following this user
          const normalizedFollowingUserId = normalizeUserId(followingUser.id);
          const isFollowing = currentUserFollowing.includes(normalizedFollowingUserId);
          
          following.push({
            id: normalizeUserId(followingUser.id), // Always return normalized ID
            email: followingUser.email || '', // Include email field for iOS decoding
            displayName: followingUser.displayName,
            profilePicture: followingUser.profilePicture || null,
            bio: followingUser.bio || null,
            firstName: followingUser.firstName || null,
            lastName: followingUser.lastName || null,
            isFollowing: isFollowing
          });
        });
      }
      
      // Log any missing following users
      const foundIds = following.map(f => f.id);
      const missingIds = normalizedFollowingIds.filter(id => !foundIds.includes(id));
      if (missingIds.length > 0) {
        console.warn('⚠️ Following users not found:', missingIds);
      }
    }
    
    res.status(200).json({
      success: true,
      count: following.length,
      following: following
    });
    
  } catch (error) {
    console.error('Error fetching following:', error);
    next(error);
  }
};

// @desc    Find and merge duplicate user accounts
// @route   POST /api/users/find-duplicates
// @access  Private (Admin only)
exports.findDuplicateAccounts = async (req, res, next) => {
  try {
    const { email, displayName } = req.body;
    const currentUserId = req.user.uid;
    
    if (!email) {
      return res.status(400).json({
        success: false,
        message: 'Email is required'
      });
    }
    
    console.log(`🔍 Finding duplicates for user: ${email} (${displayName})`);
    
    const duplicateAccounts = [];
    const currentUserEmail = email.toLowerCase();
    
    // Find accounts with same email (exact match)
    const emailQuery = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email)
      .get();
    
    emailQuery.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.id !== currentUserId) {
        duplicateAccounts.push({
          ...user,
          matchType: 'email',
          reason: 'Same email address'
        });
      }
    });
    
    // Find accounts in alternateEmails array
    const alternateEmailQuery = await db.collection(COLLECTIONS.USERS)
      .where('alternateEmails', 'array-contains', email)
      .get();
    
    alternateEmailQuery.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.id !== currentUserId && !duplicateAccounts.find(acc => acc.id === user.id)) {
        duplicateAccounts.push({
          ...user,
          matchType: 'alternateEmail',
          reason: 'Email found in alternate emails'
        });
      }
    });
    
    // Find potential Apple Sign In duplicates by displayName (if current email is private relay)
    if (email.includes('@privaterelay.appleid.com') && displayName) {
      const nameQuery = await db.collection(COLLECTIONS.USERS)
        .where('displayName', '==', displayName)
        .get();
      
      nameQuery.docs.forEach(doc => {
        const user = serializeDoc(doc);
        if (user.id !== currentUserId && 
            !user.email.includes('@privaterelay.appleid.com') && 
            !duplicateAccounts.find(acc => acc.id === user.id)) {
          duplicateAccounts.push({
            ...user,
            matchType: 'displayName',
            reason: 'Same display name (potential Apple Sign In duplicate)'
          });
        }
      });
    }
    
    // Find accounts where current email is in their alternateEmails
    if (!email.includes('@privaterelay.appleid.com')) {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      usersSnapshot.docs.forEach(doc => {
        const user = serializeDoc(doc);
        if (user.id !== currentUserId && 
            user.email && 
            user.email.includes('@privaterelay.appleid.com') &&
            user.displayName === displayName &&
            !duplicateAccounts.find(acc => acc.id === user.id)) {
          duplicateAccounts.push({
            ...user,
            matchType: 'privateRelay',
            reason: 'Private relay account with same display name'
          });
        }
      });
    }
    
    console.log(`Found ${duplicateAccounts.length} potential duplicate accounts for ${email}`);
    
    res.status(200).json({
      success: true,
      duplicateAccounts: duplicateAccounts
    });
    
  } catch (error) {
    console.error('Error finding duplicate accounts:', error);
    next(error);
  }
};

// @desc    Get potential duplicate connections for a user
// @route   GET /api/users/me/duplicate-connections
// @access  Private
exports.checkDuplicateConnections = async (req, res, next) => {
  try {
    const currentUserId = req.user.uid;
    const currentUserEmail = req.user.email;
    
    // Find all users with the same email
    const sameEmailUsers = [];
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    
    usersSnapshot.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.email && user.email.toLowerCase() === currentUserEmail.toLowerCase() && user.id !== currentUserId) {
        sameEmailUsers.push({
          id: user.id,
          email: user.email,
          displayName: user.displayName
        });
      }
    });
    
    if (sameEmailUsers.length === 0) {
      return res.status(200).json({
        success: true,
        message: 'No duplicate accounts found',
        duplicates: []
      });
    }
    
    // Get connections for all accounts with this email
    const allConnections = new Map();
    
    // Get connections for current user
    const currentUserConnections = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', currentUserId).get()
    ]);
    
    currentUserConnections.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        const conn = doc.data();
        const otherUserId = conn.userId === currentUserId ? conn.connectedUserId : conn.userId;
        allConnections.set(otherUserId, {
          connectionId: doc.id,
          status: conn.status,
          fromAccount: currentUserId
        });
      });
    });
    
    // Get connections for duplicate accounts
    for (const dupUser of sameEmailUsers) {
      const dupConnections = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', dupUser.id).get(),
        db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', dupUser.id).get()
      ]);
      
      dupConnections.forEach(snapshot => {
        snapshot.docs.forEach(doc => {
          const conn = doc.data();
          const otherUserId = conn.userId === dupUser.id ? conn.connectedUserId : conn.userId;
          
          // Check if this connection already exists from another account
          if (allConnections.has(otherUserId)) {
            console.log(`Duplicate connection found: ${otherUserId} connected to both ${currentUserId} and ${dupUser.id}`);
          }
        });
      });
    }
    
    res.status(200).json({
      success: true,
      currentUserId: currentUserId,
      duplicateAccounts: sameEmailUsers,
      message: `Found ${sameEmailUsers.length} other accounts with email ${currentUserEmail}`
    });
  } catch (error) {
    console.error('Error checking duplicate connections:', error);
    next(error);
  }
};

// @desc    Add place to pinned places
// @route   POST /api/users/me/pinned-places
// @access  Private
exports.addPinnedPlace = async (req, res, next) => {
  try {
    const { placeId } = req.body;
    
    if (!placeId) {
      return res.status(400).json({
        success: false,
        message: 'Place ID is required'
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

    const user = serializeDoc(userDoc);
    const pinnedPlaces = user.pinnedPlaces || [];
    
    // Check if place is already pinned
    if (pinnedPlaces.includes(placeId)) {
      return res.status(400).json({
        success: false,
        message: 'Place is already pinned'
      });
    }
    
    // Check max limit (6 pinned places)
    if (pinnedPlaces.length >= 6) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 6 places can be pinned'
      });
    }
    
    // Verify place exists and user has access to it
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user has access to this place (owns it or it's in their network)
    if (place.addedBy !== req.user.uid) {
      // Could add additional access checks here for network visibility
      // For now, only allow pinning own places
      return res.status(403).json({
        success: false,
        message: 'You can only pin places you have added'
      });
    }
    
    // Add to pinned places
    pinnedPlaces.push(placeId);
    
    await userRef.update({
      pinnedPlaces: pinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Place pinned successfully',
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error adding pinned place:', error);
    next(error);
  }
};

// @desc    Remove place from pinned places
// @route   DELETE /api/users/me/pinned-places/:placeId
// @access  Private
exports.removePinnedPlace = async (req, res, next) => {
  try {
    const { placeId } = req.params;
    
    if (!placeId) {
      return res.status(400).json({
        success: false,
        message: 'Place ID is required'
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

    const user = serializeDoc(userDoc);
    const pinnedPlaces = user.pinnedPlaces || [];
    
    // Check if place is pinned
    if (!pinnedPlaces.includes(placeId)) {
      return res.status(400).json({
        success: false,
        message: 'Place is not pinned'
      });
    }
    
    // Remove from pinned places
    const updatedPinnedPlaces = pinnedPlaces.filter(id => id !== placeId);
    
    await userRef.update({
      pinnedPlaces: updatedPinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Place unpinned successfully',
      pinnedPlaces: updatedPinnedPlaces
    });
    
  } catch (error) {
    console.error('Error removing pinned place:', error);
    next(error);
  }
};

// @desc    Get user's pinned places with details
// @route   GET /api/users/me/pinned-places
// @access  Private
exports.getPinnedPlaces = async (req, res, next) => {
  try {
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const pinnedPlaceIds = user.pinnedPlaces || [];
    
    if (pinnedPlaceIds.length === 0) {
      return res.status(200).json({
        success: true,
        pinnedPlaces: []
      });
    }
    
    // Fetch place details
    const pinnedPlaces = [];
    for (const placeId of pinnedPlaceIds) {
      const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      if (placeDoc.exists) {
        const place = serializeDoc(placeDoc);
        pinnedPlaces.push(place);
      }
    }
    
    res.status(200).json({
      success: true,
      count: pinnedPlaces.length,
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error fetching pinned places:', error);
    next(error);
  }
};

// @desc    Reorder pinned places
// @route   PUT /api/users/me/pinned-places/reorder
// @access  Private
exports.reorderPinnedPlaces = async (req, res, next) => {
  try {
    const { pinnedPlaces } = req.body;
    
    if (!Array.isArray(pinnedPlaces)) {
      return res.status(400).json({
        success: false,
        message: 'pinnedPlaces must be an array'
      });
    }
    
    if (pinnedPlaces.length > 6) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 6 places can be pinned'
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

    const user = serializeDoc(userDoc);
    const currentPinnedPlaces = user.pinnedPlaces || [];
    
    // Validate that all provided place IDs are currently pinned
    for (const placeId of pinnedPlaces) {
      if (!currentPinnedPlaces.includes(placeId)) {
        return res.status(400).json({
          success: false,
          message: `Place ${placeId} is not currently pinned`
        });
      }
    }
    
    // Update the order
    await userRef.update({
      pinnedPlaces: pinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Pinned places reordered successfully',
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error reordering pinned places:', error);
    next(error);
  }
};

// @desc    Get tutorial status for current user
// @route   GET /api/users/me/tutorial-status
// @access  Private
exports.getTutorialStatus = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    
    res.status(200).json({
      success: true,
      hasCompletedTutorial: userData.hasCompletedTutorial || false,
      onboardingCompleted: userData.onboardingCompleted || false
    });
  } catch (error) {
    console.error('Error getting tutorial status:', error);
    next(error);
  }
};

// @desc    Mark tutorial as completed
// @route   POST /api/users/me/complete-tutorial
// @access  Private
exports.completeTutorial = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    await userRef.update({
      hasCompletedTutorial: true,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`✅ Tutorial marked as completed for user ${userId}`);
    
    res.status(200).json({
      success: true,
      message: 'Tutorial marked as completed'
    });
  } catch (error) {
    console.error('Error completing tutorial:', error);
    next(error);
  }
};

// @desc    Retry onboarding for current user
// @route   POST /api/users/me/complete-onboarding
// @access  Private
exports.retryOnboarding = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    const OnboardingService = require('../services/onboardingService');
    
    // Check if user already has circles
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .limit(1)
      .get();
    
    if (!circlesSnapshot.empty) {
      return res.status(400).json({
        success: false,
        message: 'User already has circles'
      });
    }
    
    // Run onboarding
    const result = await OnboardingService.completeUserOnboarding(userId);
    
    if (result.success) {
      res.status(200).json({
        success: true,
        message: 'Onboarding completed successfully',
        circlesCreated: result.circlesCreated
      });
    } else {
      res.status(500).json({
        success: false,
        message: 'Onboarding failed',
        error: result.error
      });
    }
  } catch (error) {
    console.error('Error retrying onboarding:', error);
    next(error);
  }
};

// @desc    Recalculate follower/following counts for a user
// @route   POST /api/users/:id/recalculate-counts
// @access  Private (Admin or owner only)
exports.recalculateFollowerCounts = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔄 recalculateFollowerCounts called:', {
      targetUserId,
      currentUserId,
      isOwner: isSameUser(targetUserId, currentUserId)
    });
    
    // Only allow user to recalculate their own counts
    // TODO: Add admin check for admin users
    if (!isSameUser(targetUserId, currentUserId)) {
      return res.status(403).json({
        success: false,
        message: 'You can only recalculate your own follower counts'
      });
    }
    
    // Get the user document
    const userRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    
    // Calculate actual counts from arrays
    const actualFollowersCount = (userData.followers || []).length;
    const actualFollowingCount = (userData.following || []).length;
    
    // Get current counts
    const currentFollowersCount = userData.followersCount || 0;
    const currentFollowingCount = userData.followingCount || 0;
    
    console.log('📊 Count comparison:', {
      currentFollowersCount,
      actualFollowersCount,
      currentFollowingCount,
      actualFollowingCount,
      needsUpdate: currentFollowersCount !== actualFollowersCount || currentFollowingCount !== actualFollowingCount
    });
    
    // Update the counts
    await userRef.update({
      followersCount: actualFollowersCount,
      followingCount: actualFollowingCount,
      updatedAt: new Date().toISOString()
    });
    
    // Return the updated user data
    const updatedUserDoc = await userRef.get();
    const updatedUser = serializeDoc(updatedUserDoc);
    
    res.status(200).json({
      success: true,
      message: 'Follower counts recalculated successfully',
      previousCounts: {
        followers: currentFollowersCount,
        following: currentFollowingCount
      },
      updatedCounts: {
        followers: actualFollowersCount,
        following: actualFollowingCount
      },
      user: {
        id: updatedUser.id,
        displayName: updatedUser.displayName,
        email: updatedUser.email,
        followersCount: updatedUser.followersCount,
        followingCount: updatedUser.followingCount
      }
    });
    
  } catch (error) {
    console.error('Error recalculating follower counts:', error);
    next(error);
  }
};

// @desc    Merge duplicate user accounts
// @route   POST /api/users/merge-accounts
// @access  Private (Admin only or same user)
// @desc    Get daily summary data for user
// @route   GET /api/users/me/daily-summary
// @access  Private
exports.getDailySummary = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    console.log(`📊 Getting daily summary for user ${userId}`);
    
    // Import the daily summary service
    const dailySummaryService = require('../services/dailySummaryService');
    
    // Gather the user's stats (same as what's used for notifications)
    const stats = await dailySummaryService.gatherUserStats(userId);
    
    // Format the response
    const summaryData = {
      date: new Date().toISOString(),
      newPlaces: stats.newPlaces,
      newPlacesByCategory: stats.newPlacesByCategory,
      newConnections: stats.newConnections,
      unreadMessages: stats.unreadMessages,
      placeComments: stats.placeComments,
      placeLikes: stats.placeLikes,
      topContributors: stats.topContributors,
      connectionCount: stats.connectionCount,
      userPlaceCount: stats.userPlaceCount
    };
    
    console.log(`📊 Summary data gathered:`, summaryData);
    
    res.json({
      success: true,
      data: summaryData
    });
  } catch (error) {
    console.error('❌ Error getting daily summary:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get daily summary',
      error: error.message
    });
  }
};

exports.mergeUserAccounts = async (req, res, next) => {
  try {
    const { primaryAccountId, secondaryAccountId } = req.body;
    
    if (!primaryAccountId || !secondaryAccountId) {
      return res.status(400).json({
        success: false,
        message: 'Both primaryAccountId and secondaryAccountId are required'
      });
    }
    
    if (primaryAccountId === secondaryAccountId) {
      return res.status(400).json({
        success: false,
        message: 'Cannot merge account with itself'
      });
    }
    
    // Get both user documents
    const primaryRef = db.collection(COLLECTIONS.USERS).doc(primaryAccountId);
    const secondaryRef = db.collection(COLLECTIONS.USERS).doc(secondaryAccountId);
    
    const [primaryDoc, secondaryDoc] = await Promise.all([
      primaryRef.get(),
      secondaryRef.get()
    ]);
    
    if (!primaryDoc.exists || !secondaryDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'One or both user accounts not found'
      });
    }
    
    const primaryUser = serializeDoc(primaryDoc);
    const secondaryUser = serializeDoc(secondaryDoc);
    
    // Verify user has permission (admin or owns one of the accounts)
    const isAdmin = req.user.role === 'admin'; // Assuming admin role exists
    const ownsAccount = req.user.uid === primaryAccountId || req.user.uid === secondaryAccountId;
    
    if (!isAdmin && !ownsAccount) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to merge these accounts'
      });
    }
    
    console.log(`🔄 Merging accounts: ${secondaryAccountId} -> ${primaryAccountId}`);
    console.log(`Primary: ${primaryUser.email} (${primaryUser.displayName})`);
    console.log(`Secondary: ${secondaryUser.email} (${secondaryUser.displayName})`);
    
    // Prepare merged data
    const mergedData = {
      // Merge alternate emails
      alternateEmails: [
        ...(primaryUser.alternateEmails || []),
        ...(secondaryUser.alternateEmails || []),
        // Add secondary email if different from primary
        ...(secondaryUser.email && secondaryUser.email !== primaryUser.email ? [secondaryUser.email] : [])
      ].filter((email, index, arr) => arr.indexOf(email) === index && email !== primaryUser.email), // Remove duplicates and primary email
      
      // Merge linked providers
      linkedProviders: {
        ...(primaryUser.linkedProviders || {}),
        ...(secondaryUser.linkedProviders || {})
      },
      
      // Keep better display name if secondary has one and primary doesn't
      displayName: primaryUser.displayName || secondaryUser.displayName,
      
      // Keep better profile picture if secondary has one and primary doesn't
      profilePicture: primaryUser.profilePicture || secondaryUser.profilePicture,
      
      // Merge other fields intelligently
      firstName: primaryUser.firstName || secondaryUser.firstName,
      lastName: primaryUser.lastName || secondaryUser.lastName,
      phoneNumber: primaryUser.phoneNumber || secondaryUser.phoneNumber,
      bio: primaryUser.bio || secondaryUser.bio,
      location: primaryUser.location || secondaryUser.location,
      
      // Merge arrays
      followers: [...(primaryUser.followers || []), ...(secondaryUser.followers || [])].filter((id, index, arr) => arr.indexOf(id) === index),
      following: [...(primaryUser.following || []), ...(secondaryUser.following || [])].filter((id, index, arr) => arr.indexOf(id) === index),
      deviceTokens: [...(primaryUser.deviceTokens || []), ...(secondaryUser.deviceTokens || [])].filter((token, index, arr) => arr.indexOf(token) === index),
      pinnedPlaces: [...(primaryUser.pinnedPlaces || []), ...(secondaryUser.pinnedPlaces || [])].slice(0, 6), // Max 6
      
      // Update counts
      followersCount: 0, // Will be recalculated
      followingCount: 0, // Will be recalculated
      
      // Keep notification preferences from primary (user can update if needed)
      notificationPreferences: primaryUser.notificationPreferences || secondaryUser.notificationPreferences,
      
      updatedAt: new Date().toISOString()
    };
    
    // Recalculate counts
    mergedData.followersCount = mergedData.followers.length;
    mergedData.followingCount = mergedData.following.length;
    
    // Use transaction to ensure consistency
    await db.runTransaction(async (transaction) => {
      // Update primary account with merged data
      transaction.update(primaryRef, mergedData);
      
      // Update all connections that point to secondary account
      const connectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', secondaryAccountId)
        .get();
      
      const connectedToQuery = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', secondaryAccountId)
        .get();
      
      // Update connections where secondary was the user
      connectionsQuery.forEach(doc => {
        transaction.update(doc.ref, { userId: primaryAccountId });
      });
      
      // Update connections where secondary was the connected user
      connectedToQuery.forEach(doc => {
        transaction.update(doc.ref, { connectedUserId: primaryAccountId });
      });
      
      // TODO: Also update circles, places, messages, etc. that belong to secondary account
      // For now, we'll just mark the secondary account as merged
      transaction.update(secondaryRef, {
        mergedInto: primaryAccountId,
        mergedAt: new Date().toISOString(),
        active: false
      });
    });
    
    console.log(`✅ Successfully merged ${secondaryAccountId} into ${primaryAccountId}`);
    
    // Get updated primary user
    const updatedPrimaryDoc = await primaryRef.get();
    const updatedUser = serializeDoc(updatedPrimaryDoc);
    
    res.status(200).json({
      success: true,
      message: 'Accounts merged successfully',
      primaryAccount: updatedUser,
      mergedData: {
        alternateEmailsAdded: mergedData.alternateEmails.filter(email => !(primaryUser.alternateEmails || []).includes(email)),
        providersLinked: Object.keys(secondaryUser.linkedProviders || {}),
        followersAdded: (secondaryUser.followers || []).length,
        followingAdded: (secondaryUser.following || []).length
      }
    });
    
  } catch (error) {
    console.error('Error merging accounts:', error);
    next(error);
  }
};