// backend/controllers/circleSharingController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCircleShare, 
  validateCircleShare, 
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const crypto = require('crypto');

const db = getFirestore();

// @desc    Share a circle
// @route   POST /api/circles/:id/share
// @access  Private
const shareCircle = async (req, res) => {
  try {
    const userId = req.user.uid;
    const circleId = req.params.id;
    const { userId: targetUserId, email, shareType, accessLevel, expiresIn } = req.body;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to share this circle'
      });
    }

    // Prepare share data based on share type
    let shareData = {
      circleId,
      sharedBy: userId,
      shareType,
      accessLevel: accessLevel || 'view_only'
    };

    // Set expiration if provided
    if (expiresIn && typeof expiresIn === 'number') {
      const expirationDate = new Date();
      expirationDate.setDate(expirationDate.getDate() + expiresIn);
      shareData.expiresAt = expirationDate.toISOString();
    }

    // Handle different share types
    switch (shareType) {
      case 'registered_user':
        if (!targetUserId) {
          return res.status(400).json({
            success: false,
            message: 'User ID is required for registered user shares'
          });
        }

        // Verify target user exists
        const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
        if (!targetUserDoc.exists) {
          return res.status(404).json({
            success: false,
            message: 'Target user not found'
          });
        }

        // Check if already shared with this user
        const existingShare = await db.collection(COLLECTIONS.CIRCLE_SHARES)
          .where('circleId', '==', circleId)
          .where('sharedWith', '==', targetUserId)
          .where('shareType', '==', 'registered_user')
          .get();

        if (!existingShare.empty) {
          return res.status(409).json({
            success: false,
            message: 'Circle already shared with this user'
          });
        }

        shareData.sharedWith = targetUserId;
        break;

      case 'email':
        if (!email || !email.includes('@')) {
          return res.status(400).json({
            success: false,
            message: 'Valid email is required for email shares'
          });
        }

        shareData.sharedWith = email;
        break;

      case 'link':
        // Generate a secure share link
        const shareToken = crypto.randomBytes(32).toString('hex');
        // Use deep link format that will open directly in the app
        shareData.shareLink = `circles://circle/${circleId}?share=${shareToken}`;
        // Also store a web fallback URL for users who don't have the app
        shareData.webShareLink = `https://circles-app.com/shared/${circleId}/${shareToken}`;
        break;

      default:
        return res.status(400).json({
          success: false,
          message: 'Invalid share type'
        });
    }

    // Validate share data
    const errors = validateCircleShare(shareData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Create the share
    const circleShareData = createCircleShare(shareData);
    const docRef = await db.collection(COLLECTIONS.CIRCLE_SHARES).add(circleShareData);
    const newDoc = await docRef.get();
    const share = serializeDoc(newDoc);

    // Update circle's activeShares array
    const currentShares = circle.activeShares || [];
    await circleDoc.ref.update({
      activeShares: [...currentShares, docRef.id],
      updatedAt: new Date().toISOString()
    });

    // Populate related data
    if (shareType === 'registered_user' && targetUserId) {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
      if (userDoc.exists) {
        share.sharedWithUser = serializeDoc(userDoc);
      }
    }

    // Populate circle data
    share.circle = serializeDoc(circleDoc);

    res.status(201).json({
      success: true,
      data: share
    });

  } catch (error) {
    console.error('Error sharing circle:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Revoke circle share
// @route   DELETE /api/circles/:id/share/:shareId
// @access  Private
const revokeShare = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { id: circleId, shareId } = req.params;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to revoke shares for this circle'
      });
    }

    // Get and verify share exists
    const shareDoc = await db.collection(COLLECTIONS.CIRCLE_SHARES).doc(shareId).get();
    
    if (!shareDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Share not found'
      });
    }

    const share = shareDoc.data();
    
    if (share.circleId !== circleId) {
      return res.status(400).json({
        success: false,
        message: 'Share does not belong to this circle'
      });
    }

    // Delete the share
    await shareDoc.ref.delete();

    // Update circle's activeShares array
    const currentShares = circle.activeShares || [];
    const updatedShares = currentShares.filter(id => id !== shareId);
    await circleDoc.ref.update({
      activeShares: updatedShares,
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Share revoked successfully'
    });

  } catch (error) {
    console.error('Error revoking share:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get all shares for a circle
// @route   GET /api/circles/:id/shares
// @access  Private
const getCircleShares = async (req, res) => {
  try {
    const userId = req.user.uid;
    const circleId = req.params.id;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view shares for this circle'
      });
    }

    // Get all shares for this circle
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();

    // Serialize and populate user data
    const shares = await Promise.all(
      sharesQuery.docs.map(async (doc) => {
        const share = serializeDoc(doc);
        
        // Populate shared with user data if it's a registered user
        if (share.shareType === 'registered_user' && share.sharedWith) {
          try {
            const userDoc = await db.collection(COLLECTIONS.USERS).doc(share.sharedWith).get();
            if (userDoc.exists) {
              share.sharedWithUser = serializeDoc(userDoc);
            }
          } catch (error) {
            console.error(`Error fetching user ${share.sharedWith}:`, error);
          }
        }

        return share;
      })
    );

    res.status(200).json({
      success: true,
      data: shares
    });

  } catch (error) {
    console.error('Error fetching circle shares:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get all shared circles for user
// @route   GET /api/network/shared-circles
// @access  Private
const getSharedCircles = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all shares created by this user
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('sharedBy', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();

    // Group shares by circle
    const sharesByCircle = {};
    const circleIds = new Set();

    sharesQuery.docs.forEach(doc => {
      const share = serializeDoc(doc);
      const circleId = share.circleId;
      
      if (!sharesByCircle[circleId]) {
        sharesByCircle[circleId] = [];
      }
      sharesByCircle[circleId].push(share);
      circleIds.add(circleId);
    });

    // Fetch circle details
    const circlePromises = Array.from(circleIds).map(id => 
      db.collection(COLLECTIONS.CIRCLES).doc(id).get()
    );
    
    const circleDocs = await Promise.all(circlePromises);
    
    // Build response with share data
    const result = circleDocs
      .filter(doc => doc.exists)
      .map(doc => {
        const circle = serializeDoc(doc);
        circle.activeShares = sharesByCircle[circle._id] || [];
        return circle;
      });

    res.status(200).json({
      success: true,
      data: result
    });

  } catch (error) {
    console.error('Error fetching shared circles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Update share access time (for analytics)
// @route   POST /api/circles/share/:shareId/access
// @access  Public (for shared links)
const updateShareAccess = async (req, res) => {
  try {
    const { shareId } = req.params;

    const shareDoc = await db.collection(COLLECTIONS.CIRCLE_SHARES).doc(shareId).get();
    
    if (!shareDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Share not found'
      });
    }

    const share = shareDoc.data();
    
    // Check if share is expired
    if (share.expiresAt && new Date(share.expiresAt) < new Date()) {
      return res.status(410).json({
        success: false,
        message: 'Share has expired'
      });
    }

    // Update last accessed time
    await shareDoc.ref.update({
      lastAccessedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Access recorded'
    });

  } catch (error) {
    console.error('Error updating share access:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get circles shared with me that allow editing
// @route   GET /api/network/circles-shared-with-me
// @access  Private
const getCirclesSharedWithMe = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all connections for the current user (where they are either userId or connectedUserId)
    const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get();
      
    const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get();

    // Get connected user IDs
    const connectedUserIds = new Set();
    
    // Add users from connections where current user is userId
    connectionsQuery1.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.connectedUserId);
    });
    
    // Add users from connections where current user is connectedUserId
    connectionsQuery2.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.userId);
    });

    if (connectedUserIds.size === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get circles from connected users where allowNetworkEdit is true
    const circlesQuery = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', 'in', Array.from(connectedUserIds))
      .where('allowNetworkEdit', '==', true)
      .get();

    // Build response with circle data
    const circles = [];
    for (const doc of circlesQuery.docs) {
      const circle = serializeDoc(doc);
      
      // Get owner details
      const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(circle.owner).get();
      if (ownerDoc.exists) {
        circle.ownerDetails = serializeDoc(ownerDoc);
      }
      
      circles.push(circle);
    }

    res.status(200).json({
      success: true,
      data: circles
    });

  } catch (error) {
    console.error('Error fetching circles shared with me:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get all non-private circles from my network connections (public and myNetwork privacy)
// @route   GET /api/network/my-network-circles
// @access  Private
const getMyNetworkCircles = async (req, res) => {
  try {
    const userId = req.user.uid;
    console.log('🔍 Getting network circles for user:', userId);

    // Get all connections for the current user (where they are either userId or connectedUserId)
    const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get();
      
    const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get();

    console.log('📊 Found connections as userId:', connectionsQuery1.size);
    console.log('📊 Found connections as connectedUserId:', connectionsQuery2.size);

    // Get connected user IDs
    const connectedUserIds = new Set();
    
    // Add users from connections where current user is userId
    connectionsQuery1.docs.forEach(doc => {
      const connection = doc.data();
      console.log('Connection (as userId):', connection.userId, '->', connection.connectedUserId);
      connectedUserIds.add(connection.connectedUserId);
    });
    
    // Add users from connections where current user is connectedUserId
    connectionsQuery2.docs.forEach(doc => {
      const connection = doc.data();
      console.log('Connection (as connectedUserId):', connection.userId, '<-', connection.connectedUserId);
      connectedUserIds.add(connection.userId);
    });

    console.log('👥 Connected user IDs:', Array.from(connectedUserIds));

    if (connectedUserIds.size === 0) {
      console.log('⚠️ No connections found for user:', userId);
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get circles from connected users with non-private privacy (public or myNetwork)
    const circlesQuery = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', 'in', Array.from(connectedUserIds))
      .where('privacy', 'in', ['public', 'myNetwork'])
      .get();
    
    console.log('🔵 Found circles from connections:', circlesQuery.size);

    // Serialize all circles first
    const circles = circlesQuery.docs.map(doc => serializeDoc(doc));
    
    // OPTIMIZATION: Batch fetch all unique owner IDs
    const uniqueOwnerIds = [...new Set(circles.map(circle => circle.owner))];
    console.log('🚀 Batch fetching', uniqueOwnerIds.length, 'unique owners');
    
    let ownersMap = new Map();
    
    // Firestore 'in' operator has a limit of 10 items, so we need to batch the requests
    const ownerBatches = [];
    for (let i = 0; i < uniqueOwnerIds.length; i += 10) {
      ownerBatches.push(uniqueOwnerIds.slice(i, i + 10));
    }
    
    // Fetch all owner details in parallel batches
    const ownerResults = await Promise.all(
      ownerBatches.map(batch => 
        db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', batch)
          .get()
      )
    );
    
    // Combine all results into the map
    ownerResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        ownersMap.set(doc.id, serializeDoc(doc));
      });
    });
    
    // Enrich circles with owner details from map
    circles.forEach(circle => {
      circle.ownerDetails = ownersMap.get(circle.owner) || null;
    });

    console.log('✅ Returning', circles.length, 'circles with batch-loaded owner details');

    res.status(200).json({
      success: true,
      data: circles
    });

  } catch (error) {
    console.error('Error fetching my network circles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get connected users with their circle counts
// @route   GET /api/network/users-with-circles
// @access  Private
const getUsersWithCircles = async (req, res) => {
  try {
    const userId = req.user.uid;
    console.log('🔍 Getting users with circles for:', userId);

    // Get all connections for the current user
    const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get();
      
    const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get();

    // Get connected user IDs
    const connectedUserIds = new Set();
    
    connectionsQuery1.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.connectedUserId);
    });
    
    connectionsQuery2.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.userId);
    });

    if (connectedUserIds.size === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get user details and circle counts
    const usersWithCircles = [];
    
    for (const connectedUserId of connectedUserIds) {
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(connectedUserId).get();
      if (!userDoc.exists) continue;
      
      const userData = serializeDoc(userDoc);
      
      // Get count of non-private circles for this user
      const circlesQuery = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', connectedUserId)
        .where('privacy', 'in', ['public', 'myNetwork'])
        .get();
      
      usersWithCircles.push({
        userId: userData.id,
        displayName: userData.displayName,
        profilePicture: userData.profilePicture,
        email: userData.email,
        location: userData.location,
        circleCount: circlesQuery.size
      });
    }

    // Sort by circle count (descending) then by name
    usersWithCircles.sort((a, b) => {
      if (b.circleCount !== a.circleCount) {
        return b.circleCount - a.circleCount;
      }
      return a.displayName.localeCompare(b.displayName);
    });

    res.status(200).json({
      success: true,
      data: usersWithCircles
    });

  } catch (error) {
    console.error('Error fetching users with circles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get circles for a specific connected user
// @route   GET /api/network/user-circles/:userId
// @access  Private
const getUserCircles = async (req, res) => {
  try {
    const currentUserId = req.user.uid;
    const targetUserId = req.params.userId;
    
    // Import activityService at function level to ensure it's always in scope
    const activityService = require('../services/activityService');
    
    console.log('getUserCircles called:', { currentUserId, targetUserId });

    // Check if users are connected OR if current user is following target user
    const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', currentUserId)
      .where('connectedUserId', '==', targetUserId)
      .where('status', '==', 'accepted')
      .get();
      
    const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', targetUserId)
      .where('connectedUserId', '==', currentUserId)
      .where('status', '==', 'accepted')
      .get();

    const isConnected = !connection1.empty || !connection2.empty;
    let isFollowing = false;

    // If not connected, check if current user is following target user
    if (!isConnected) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      if (currentUserDoc.exists) {
        const currentUserData = currentUserDoc.data();
        const following = currentUserData?.following || [];
        isFollowing = following.includes(targetUserId);
      }
    }

    console.log(`🔍 Permission check - Connected: ${isConnected}, Following: ${isFollowing}`);

    // Allow access if user is connected OR following
    if (!isConnected && !isFollowing) {
      return res.status(403).json({
        success: false,
        message: 'You are not connected to this user and not following them'
      });
    }
    
    // Get the connection document to check for recent activity (only exists for connections)
    const connectionDoc = !connection1.empty ? connection1.docs[0] : (!connection2.empty ? connection2.docs[0] : null);
    const connectionData = connectionDoc ? connectionDoc.data() : null;
    
    // Track that the user viewed this connection (only for actual connections)
    if (isConnected) {
      await activityService.trackConnectionView(currentUserId, targetUserId);
    }

    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userData = serializeDoc(userDoc);

    // Get the user's connections count
    const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', targetUserId)
      .where('status', '==', 'accepted')
      .get();
      
    const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', targetUserId)
      .where('status', '==', 'accepted')
      .get();
    
    // Count unique connections (avoid duplicates)
    const connectionIds = new Set();
    connectionsQuery1.docs.forEach(doc => {
      connectionIds.add(doc.data().connectedUserId);
    });
    connectionsQuery2.docs.forEach(doc => {
      connectionIds.add(doc.data().userId);
    });
    
    userData.connectionsCount = connectionIds.size;

    // Check if current user is following target user
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
    if (currentUserDoc.exists) {
      const currentUserData = currentUserDoc.data();
      const following = currentUserData.following || [];
      userData.isFollowing = following.includes(targetUserId);
      console.log(`🔍 Follow check - Current user ${currentUserId} following ${targetUserId}: ${userData.isFollowing}`);
    } else {
      userData.isFollowing = false;
    }

    // Get circles based on relationship type
    let allowedPrivacyLevels = [];
    if (isConnected) {
      // Connected users can see both public and myNetwork circles
      allowedPrivacyLevels = ['public', 'myNetwork'];
    } else if (isFollowing) {
      // Followers can only see public circles
      allowedPrivacyLevels = ['public'];
    }

    const circlesQuery = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', targetUserId)
      .where('privacy', 'in', allowedPrivacyLevels)
      .get();
    
    // Sort in memory for now until Firestore index is created
    const sortedDocs = circlesQuery.docs.sort((a, b) => {
      const aDate = a.data().updatedAt || a.data().createdAt;
      const bDate = b.data().updatedAt || b.data().createdAt;
      return bDate.localeCompare(aDate);
    });

    // Get recent activity from connection data (empty for fake profiles)
    const recentActivity = connectionData?.recentActivity || [];
    
    // Filter activities that haven't been viewed by the current user
    const unviewedActivities = recentActivity.filter(activity => {
      const viewedBy = activity.viewedBy || [];
      return !viewedBy.includes(currentUserId);
    });
    
    // Create sets of unviewed circle and place IDs for easy lookup
    const unviewedCircleIds = new Set(
      unviewedActivities
        .filter(a => a.type === 'circle')
        .map(a => a.entityId)
    );
    
    const unviewedPlaceIds = new Set(
      unviewedActivities
        .filter(a => a.type === 'place')
        .map(a => a.entityId)
    );
    
    // Create a map of circleId -> array of unviewed place activities
    const unviewedPlacesByCircle = new Map();
    unviewedActivities
      .filter(a => a.type === 'place' && a.circleId)
      .forEach(activity => {
        if (!unviewedPlacesByCircle.has(activity.circleId)) {
          unviewedPlacesByCircle.set(activity.circleId, []);
        }
        unviewedPlacesByCircle.get(activity.circleId).push(activity);
      });

    // Fetch places for each circle
    const circles = await Promise.all(sortedDocs.map(async doc => {
      const circle = serializeDoc(doc);
      circle.ownerDetails = userData;
      
      // Mark if this circle is new (unviewed)
      circle.isNew = unviewedCircleIds.has(circle._id);
      
      // Check if this circle has any unviewed places
      circle.hasNewPlaces = unviewedPlacesByCircle.has(circle._id);
      circle.newPlacesCount = unviewedPlacesByCircle.get(circle._id)?.length || 0;
      
      // Only fetch places for circles with appropriate privacy settings
      if (circle.privacy === 'myNetwork' || circle.privacy === 'public') {
        try {
          // Try with index first
          const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
            .where('circleId', '==', circle._id)
            .orderBy('createdAt', 'desc')
            .get();
            
          // Return both place IDs and full details in separate fields
          circle.places = placesSnapshot.docs.map(doc => doc.id);
          circle.placesWithDetails = serializeQuerySnapshot(placesSnapshot);
          
          // Mark which places are new
          circle.placesWithDetails = circle.placesWithDetails.map(place => ({
            ...place,
            isNew: unviewedPlaceIds.has(place._id)
          }));
        } catch (indexError) {
          // Fallback: fetch without orderBy and sort in memory
          console.log(`Index not ready, using fallback for circle ${circle._id}`);
          const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
            .where('circleId', '==', circle._id)
            .get();
            
          const sortedDocs = placesSnapshot.docs
            .sort((a, b) => {
              const aDate = new Date(a.data().createdAt || 0);
              const bDate = new Date(b.data().createdAt || 0);
              return bDate - aDate;
            });
          
          circle.places = sortedDocs.map(doc => doc.id);
          circle.placesWithDetails = sortedDocs.map(doc => {
            const place = serializeDoc(doc);
            return {
              ...place,
              isNew: unviewedPlaceIds.has(place._id)
            };
          });
        }
      } else {
        circle.places = [];
        circle.placesWithDetails = [];
      }
      
      return circle;
    }));

    // Clear activity notification after viewing
    await activityService.clearActivityNotification(currentUserId, targetUserId);
    
    res.status(200).json({
      success: true,
      data: {
        user: userData,
        circles: circles,
        hasRecentActivity: connectionData ? (connectionData.hasNewActivity || connectionData.hasRecentPlace || false) : false
      }
    });

  } catch (error) {
    console.error('Error fetching user circles:', error);
    console.error('Full error details:', JSON.stringify(error, null, 2));
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Validate a share token
// @route   POST /api/circles/share/validate
// @access  Public (for validating share links)
const validateShareToken = async (req, res) => {
  try {
    const { circleId, shareToken } = req.body;

    if (!circleId || !shareToken) {
      return res.status(400).json({
        success: false,
        isValid: false,
        message: 'Circle ID and share token are required'
      });
    }

    // Find share by circle ID and token
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('circleId', '==', circleId)
      .where('shareType', '==', 'link')
      .get();

    let validShare = null;
    
    // Check each share to find one with matching token
    for (const doc of sharesQuery.docs) {
      const share = doc.data();
      
      // Extract token from share link
      if (share.shareLink) {
        const tokenMatch = share.shareLink.match(/share=([^&]+)/);
        if (tokenMatch && tokenMatch[1] === shareToken) {
          validShare = { id: doc.id, ...share };
          break;
        }
      }
    }

    if (!validShare) {
      return res.status(404).json({
        success: false,
        isValid: false,
        message: 'Invalid share link'
      });
    }

    // Check if share is expired
    if (validShare.expiresAt && new Date(validShare.expiresAt) < new Date()) {
      return res.status(410).json({
        success: false,
        isValid: false,
        message: 'This share link has expired'
      });
    }

    // Update last accessed time
    await db.collection(COLLECTIONS.CIRCLE_SHARES).doc(validShare.id).update({
      lastAccessedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    // Return validation result
    res.status(200).json({
      success: true,
      isValid: true,
      accessLevel: validShare.accessLevel || 'view_only',
      message: 'Share link is valid'
    });

  } catch (error) {
    console.error('Error validating share token:', error);
    res.status(500).json({
      success: false,
      isValid: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  shareCircle,
  revokeShare,
  getCircleShares,
  getSharedCircles,
  updateShareAccess,
  getCirclesSharedWithMe,
  getMyNetworkCircles,
  getUsersWithCircles,
  getUserCircles,
  validateShareToken
};