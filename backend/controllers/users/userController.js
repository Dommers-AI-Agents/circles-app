// backend/controllers/users/userController.js
// profile read/update, user search, circle order, public circles, daily summary
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../../models/FirestoreModels');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const { buildConnectionMap } = require('../../services/connectionMap');

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

    // "Show my city" preference: hide the location from everyone but the
    // owner when switched off (default is shown)
    const locationHidden = !isOwnProfile
      && user.preferences && user.preferences.showLocation === false;

    const profileData = {
      _id: normalizeUserId(user.id), // Always return normalized ID
      displayName: user.displayName,
      profilePicture: user.profilePicture,
      bio: user.bio,
      location: locationHidden ? null : user.location,
      createdAt: user.createdAt,
      followersCount: user.followersCount || 0,
      followingCount: user.followingCount || 0
    };

    // Brand storefront is public presentation — any viewer's profile screen
    // renders the store card and lists show the store chip off these fields
    if (user.storefront && user.storefront.enabled === true) {
      profileData.isBusiness = true;
      profileData.storefront = {
        businessName: user.storefront.businessName,
        about: user.storefront.about || null,
        website: user.storefront.website || null,
        catalogUrl: user.storefront.catalogUrl || null,
        contactEmail: user.storefront.contactEmail || null,
        findUsAtCircleId: user.storefront.findUsAtCircleId || null
      };
    }

    // Include private data only for own profile
    if (isOwnProfile) {
      profileData.email = user.email;
      profileData.firstName = user.firstName || null;
      profileData.lastName = user.lastName || null;
      profileData.phoneNumber = user.phoneNumber || null;
      profileData.zipcode = user.zipcode || null;
      profileData.friends = user.friends;
      profileData.friendRequests = user.friendRequests;
      profileData.followers = user.followers;
      profileData.following = user.following;
      profileData.deviceTokens = user.deviceTokens; // Include device tokens for own profile
      profileData.preferences = user.preferences || null;
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
    const { displayName, firstName, lastName, phoneNumber, bio, location, zipcode, profilePicture, preferences } = req.body;

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
    if (zipcode !== undefined) updateData.zipcode = zipcode;

    // The zipcode is the source of truth for the profile location: whenever a
    // valid one is saved, derive "City, ST" and write it — overriding any
    // free-text location in the same request. Registration already did this;
    // profile edits and the silent zipcode capture didn't, which is how
    // profiles ended up with a zipcode and no city, or a zipcode from one
    // state and a city from another.
    const zipTrimmed = typeof zipcode === 'string' ? zipcode.trim() : '';
    if (/^\d{5}$/.test(zipTrimmed)) {
      try {
        const { geocodeZipcode } = require('../../services/zipcodeService');
        const derived = await geocodeZipcode(zipTrimmed);
        if (derived && derived.city && derived.state) {
          updateData.location = `${derived.city}, ${derived.state}`;
          console.log(`📍 Derived location from zipcode ${zipTrimmed}: ${updateData.location}`);
        }
      } catch (zipError) {
        console.warn('⚠️ Zipcode→location derivation failed:', zipError.message);
      }
    }

    // App preferences: allowlisted keys only, written as dot-path updates so a
    // partial preference write never clobbers sibling preference keys
    if (preferences && typeof preferences === 'object' && !Array.isArray(preferences)) {
      if (preferences.defaultHomeView !== undefined && typeof preferences.defaultHomeView === 'string') {
        updateData['preferences.defaultHomeView'] = preferences.defaultHomeView;
      }
      // Privacy: whether other people see this user's city on their profile
      // and on people cards (default true when absent)
      if (typeof preferences.showLocation === 'boolean') {
        updateData['preferences.showLocation'] = preferences.showLocation;
      }
    }
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

    // Piggy bank: first time the profile is complete (photo + bio). This is
    // the endpoint iOS actually saves profiles through — the same hook in
    // firebaseAuthController.updateProfile covers the legacy auth/me path;
    // the one-time dedup key makes double-crediting impossible.
    if (user.profilePicture && user.bio) {
      require('../../services/piggyBankService').credit({
        userId: userDoc.id,
        eventType: 'profile_completed',
        sourceRef: {}
      }).catch(() => {});
    }

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
        zipcode: user.zipcode || null,
        followersCount: user.followersCount || 0,
        followingCount: user.followingCount || 0,
        preferences: user.preferences || null,
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

// @desc    Search users by email, name, or phone
// @route   GET /api/users/search
// @access  Private

exports.searchUsers = async (req, res, next) => {
  try {
    const { query } = req.query;
    const currentUserId = req.user.uid; // Already normalized by middleware

    // If no query provided, return all users sorted alphabetically
    if (!query || query.trim().length === 0) {
      const [usersSnapshot, connectionMap, currentUserDoc] = await Promise.all([
        db.collection(COLLECTIONS.USERS).get(),
        buildConnectionMap(currentUserId),
        db.collection(COLLECTIONS.USERS).doc(currentUserId).get()
      ]);

      const allUsers = [];
      const currentData = currentUserDoc.exists ? currentUserDoc.data() : {};
      const following = currentData.following || [];
      // Who follows the caller. Already in the doc above, so surfacing the
      // mutual-follow state costs nothing.
      const myFollowers = new Set(currentData.followers || []);

      for (const doc of usersSnapshot.docs) {
        const user = serializeDoc(doc);

        // Skip current user - use isSameUser to handle all ID formats
        if (isSameUser(user.id, currentUserId)) continue;

        const targetUserId = normalizeUserId(user.id);
        const conn = connectionMap.get(targetUserId) || {};
        const connectionStatus = conn.status || 'none';
        const connectionDirection = conn.direction || null;
        const connectionId = conn.connectionId || null;
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
          isFollowing: isFollowing,
          followsYou: myFollowers.has(targetUserId)
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

    // Search users by email, name, or phone. Fetch the user collection, the
    // caller's connection map, and their following list together (one batch).
    const [usersSnapshot, connectionMap, currentUserDoc] = await Promise.all([
      db.collection(COLLECTIONS.USERS).get(),
      buildConnectionMap(currentUserId),
      db.collection(COLLECTIONS.USERS).doc(currentUserId).get()
    ]);

    const simpleUserId = normalizeUserId(currentUserId);
    const currentData = currentUserDoc.exists ? currentUserDoc.data() : {};
    const following = currentData.following || [];
    const myFollowers = new Set(currentData.followers || []);

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
      
      // Substring match on email/name — prefix-only made "mith" miss "Smith"
      // and half-remembered names unfindable (relevance ranking below still
      // puts prefix matches first)
      const emailMatch = user.email && user.email.toLowerCase().includes(searchTerm);
      const displayNameMatch = user.displayName && user.displayName.toLowerCase().includes(searchTerm);
      const firstNameMatch = user.firstName && user.firstName.toLowerCase().includes(searchTerm);
      const lastNameMatch = user.lastName && user.lastName.toLowerCase().includes(searchTerm);
      // Phone match ONLY when the query actually contains digits. Previously
      // a text query (e.g. "william") stripped to "" and every phone number
      // ".startsWith('')" → true, so everyone with a phone matched.
      const queryDigits = searchTerm.replace(/\D/g, '');
      const phoneMatch = queryDigits.length >= 3 && user.phoneNumber &&
        user.phoneNumber.replace(/\D/g, '').includes(queryDigits);
      
      // Also check if any word in display name starts with search term
      const displayNameWords = user.displayName ? user.displayName.toLowerCase().split(' ') : [];
      const wordMatch = displayNameWords.some(word => word.startsWith(searchTerm));
      
      if (emailMatch || displayNameMatch || firstNameMatch || lastNameMatch || phoneMatch || wordMatch) {
        const targetUserId = normalizeUserId(user.id);
        const conn = connectionMap.get(targetUserId) || {};
        const connectionStatus = conn.status || 'none';
        const connectionDirection = conn.direction || null;
        const connectionId = conn.connectionId || null;
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
          isFollowing: isFollowing,
          followsYou: myFollowers.has(targetUserId)
        });
      }
    }

    // Sort by relevance: exact name/email, then name-prefix, then a word in
    // the name starting with the query, then email-prefix, then everything
    // else (e.g. phone-only) — alphabetical within each tier.
    const relevanceRank = (u) => {
      const name = (u.displayName || '').toLowerCase();
      const email = (u.email || '').toLowerCase();
      if (name === searchTerm || email === searchTerm) return 0;
      if (name.startsWith(searchTerm)) return 1;
      if (name.split(' ').some(w => w.startsWith(searchTerm))) return 2;
      if (email.startsWith(searchTerm)) return 3;
      return 4;
    };
    matchingUsers.sort((a, b) => {
      const ra = relevanceRank(a);
      const rb = relevanceRank(b);
      if (ra !== rb) return ra - rb;
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
    const dailySummaryService = require('../../services/dailySummaryService');
    
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
