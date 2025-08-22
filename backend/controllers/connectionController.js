// backend/controllers/connectionController.js
const { getFirestore } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { 
  COLLECTIONS, 
  createConnection, 
  validateConnection, 
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const activityService = require('../services/activityService');
const notificationService = require('../services/notificationService');
const sseService = require('../services/sseService');
const scoringService = require('../services/scoringService');
const { normalizeUserId, isSameUser } = require('../services/idService');

const db = getFirestore();

// @desc    Get specific connection by ID
// @route   GET /api/connections/:connectionId
// @access  Private
const getConnectionById = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const { connectionId } = req.params;
    
    console.log(`🔍 getConnectionById - userId: ${userId}, connectionId: ${connectionId}`);

    // Get the connection document
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = serializeDoc(connectionDoc);
    
    // Verify user is part of this connection
    if (!isSameUser(connection.userId, userId) && !isSameUser(connection.connectedUserId, userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this connection'
      });
    }

    res.status(200).json({
      success: true,
      connection: connection
    });
  } catch (error) {
    console.error('❌ Error fetching connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get user connections
// @route   GET /api/connections
// @access  Private
const getConnections = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    console.log(`🔍 getConnections - userId: ${userId}`);

    // Get connections where user is either the requester or the target
    const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId);
      
    const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId);

    const [snapshot1, snapshot2] = await Promise.all([
      connectionsQuery1.get(),
      connectionsQuery2.get()
    ]);

    // Combine results and remove duplicates
    const allConnections = [...snapshot1.docs, ...snapshot2.docs];
    const uniqueConnections = allConnections.filter((doc, index, self) => 
      index === self.findIndex(d => d.id === doc.id)
    );

    // Serialize and populate user data with activity stats
    const connections = await Promise.all(
      uniqueConnections.map(async (doc) => {
        const connection = serializeDoc(doc);
        
        // Determine which user is the "other" user
        const otherUserIdRaw = connection.userId === userId ? connection.connectedUserId : connection.userId;
        // Normalize the ID before looking up the user
        const otherUserId = normalizeUserId(otherUserIdRaw);
        
        // Fetch the other user's data
        try {
          console.log(`🔍 Fetching connected user data for ID: ${otherUserId} (original: ${otherUserIdRaw})`);
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(otherUserId).get();
          if (userDoc.exists) {
            connection.connectedUser = serializeDoc(userDoc);
            // DO NOT overwrite connectedUserId - it should remain as stored in database
            console.log(`✅ Found connected user: ${connection.connectedUser.displayName}`);
            
            // Always add activity stats to properly sort connections
            // Get total places count for connected user
            const userCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
              .where('owner', '==', otherUserId)
              .get();
            
            let totalPlaces = 0;
            for (const circleDoc of userCirclesSnapshot.docs) {
              const circleData = circleDoc.data();
              totalPlaces += (circleData.places || []).length;
            }
            
            // Check for unviewed activities (Instagram-style)
            const recentActivity = connection.recentActivity || [];
            const hasUnviewedActivity = recentActivity.some(activity => {
              // Check if this user hasn't viewed this activity yet
              const viewedBy = activity.viewedBy || [];
              return !viewedBy.includes(userId);
            });
            
            // Count unviewed activities by type
            const unviewedCounts = {
              places: 0,
              circles: 0,
              suggestions: 0
            };
            
            recentActivity.forEach(activity => {
              const viewedBy = activity.viewedBy || [];
              if (!viewedBy.includes(userId)) {
                if (activity.type === 'place') unviewedCounts.places++;
                else if (activity.type === 'circle') unviewedCounts.circles++;
                else if (activity.type === 'suggestion') unviewedCounts.suggestions++;
              }
            });
            
            // Unviewed activities calculated
            
            // Replace hasRecentPlace with hasUnviewedActivity
            const calculatedHasRecentPlace = hasUnviewedActivity;
            
            // Add stats to connection - ALWAYS override with calculated value
            connection.totalPlaces = totalPlaces;
            connection.hasRecentPlace = calculatedHasRecentPlace; // Now means hasUnviewedActivity
            connection.hasUnviewedActivity = hasUnviewedActivity;
            connection.unviewedCounts = unviewedCounts;
            
            // Log for debugging
            if (connection.hasRecentPlace !== calculatedHasRecentPlace) {
              // Overriding hasRecentPlace with calculated value
            }
            connection.viewCount = connection.viewCount || 0;
            
            // Calculate connection score
            const scoreData = scoringService.calculateConnectionScore(connection, userId);
            connection.connectionScore = scoreData.score;
            connection.scoreComponents = scoreData.components;
            connection.scoreLastCalculated = scoreData.calculatedAt;
            
            // Connection stats calculated
          } else {
            console.log(`⚠️ Connected user not found for ID: ${otherUserId}`);
          }
        } catch (error) {
          console.error(`❌ Error fetching user ${otherUserId}:`, error);
        }

        return connection;
      })
    );

    res.status(200).json({
      success: true,
      connections: connections.filter(conn => conn.connectedUser) // Only return connections with valid user data
    });
  } catch (error) {
    console.error('Error fetching connections:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Send connection request
// @route   POST /api/connections/invite
// @access  Private
const sendConnectionRequest = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const { targetUserId, message, autoAccept } = req.body;
    
    console.log(`🔗 Connection request:`, {
      fromUserId: userId,
      toTargetUserId: targetUserId,
      autoAccept: autoAccept,
      message: message,
      userObj: { uid: req.user.uid, firebaseDocId: req.user.firebaseDocId, originalUid: req.user.originalUid }
    });

    // Validate input
    if (!targetUserId) {
      return res.status(400).json({
        success: false,
        message: 'Target user ID is required'
      });
    }

    // Normalize target user ID using centralized function
    const actualTargetUserId = normalizeUserId(targetUserId);
    if (actualTargetUserId !== targetUserId) {
      console.log(`🔄 Normalized target user ID from ${targetUserId} to ${actualTargetUserId}`);
    } else {
      console.log(`✅ Using target user ID as-is: ${actualTargetUserId}`);
    }

    // Check for self-connection with more robust comparison
    const normalizedCurrentUserId = normalizeUserId(userId);
    const normalizedTargetUserId = normalizeUserId(actualTargetUserId);
    
    if (normalizedCurrentUserId === normalizedTargetUserId || 
        actualTargetUserId === userId ||
        targetUserId === userId ||
        isSameUser(userId, targetUserId)) {
      console.log(`🚫 Prevented self-connection attempt:`, {
        userId,
        targetUserId,
        actualTargetUserId,
        normalizedCurrentUserId,
        normalizedTargetUserId
      });
      return res.status(400).json({
        success: false,
        message: 'Cannot connect to yourself'
      });
    }

    // Check if target user exists
    console.log(`Checking if target user exists with ID: ${actualTargetUserId}`);
    
    // First try direct lookup
    let targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(actualTargetUserId).get();
    
    // If not found, try to find by complex ID pattern
    if (!targetUserDoc.exists) {
      console.log(`Direct lookup failed, searching for user with pattern containing: ${actualTargetUserId}`);
      
      // Query for users where the document ID contains the simple ID
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      let foundUser = null;
      
      for (const doc of usersSnapshot.docs) {
        const docId = doc.id;
        // Check if this document ID contains our simple ID
        if (docId.includes(actualTargetUserId)) {
          // Verify it matches the expected pattern: prefix.simpleId.suffix
          const parts = docId.split('.');
          if (parts.length >= 2 && parts[1] === actualTargetUserId) {
            foundUser = doc;
            console.log(`Found user with complex ID: ${docId}`);
            break;
          }
        }
      }
      
      if (foundUser) {
        targetUserDoc = foundUser;
      } else {
        console.error(`Target user not found with ID: ${actualTargetUserId}`);
        return res.status(404).json({
          success: false,
          message: 'Target user not found',
          targetUserId: actualTargetUserId,
          originalTargetUserId: targetUserId
        });
      }
    }
    console.log(`✅ Target user found:`, {
      id: targetUserDoc.id,
      displayName: targetUserDoc.data().displayName,
      email: targetUserDoc.data().email
    });

    // Use the actual document ID for connection checks
    const targetUserDocId = targetUserDoc.id;
    
    // Check if connection already exists
    // We need to check all possible combinations of ID formats
    console.log(`🔍 Checking for existing connections between:`, {
      currentUser: userId,
      targetUser: targetUserDocId,
      normalizedCurrent: normalizeUserId(userId),
      normalizedTarget: normalizeUserId(targetUserDocId)
    });
    
    // Get all connections involving the current user
    const userConnectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .get();
    
    const connectedUserConnectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .get();
    
    // Check if any existing connection matches our target user
    let existingConnection = null;
    
    // Check connections where current user is the initiator
    for (const doc of userConnectionsQuery.docs) {
      const conn = doc.data();
      if (isSameUser(conn.connectedUserId, targetUserDocId)) {
        existingConnection = doc;
        console.log(`✅ Found existing connection (user as initiator):`, {
          connectionId: doc.id,
          status: conn.status
        });
        break;
      }
    }
    
    // Check connections where current user is the recipient
    if (!existingConnection) {
      for (const doc of connectedUserConnectionsQuery.docs) {
        const conn = doc.data();
        if (isSameUser(conn.userId, targetUserDocId)) {
          existingConnection = doc;
          console.log(`✅ Found existing connection (user as recipient):`, {
            connectionId: doc.id,
            status: conn.status
          });
          break;
        }
      }
    }
    
    if (existingConnection) {
      const connectionData = existingConnection.data();
      
      if (connectionData.status === 'accepted') {
        const connection = serializeDoc(existingConnection);
        connection.connectedUser = serializeDoc(targetUserDoc);
        return res.status(200).json({
          success: true,
          data: connection,
          message: 'Already connected'
        });
      }
      
      console.log(`⚠️ Connection request already exists with status: ${connectionData.status}`);
      return res.status(409).json({
        success: false,
        message: 'Connection request already pending',
        connectionId: existingConnection.id,
        status: connectionData.status
      });
    }
    
    console.log(`✅ No existing connection found, proceeding to create new connection`);

    // Final safety check before creating connection
    if (userId === targetUserDocId || isSameUser(userId, targetUserDocId)) {
      console.log(`🚫 Final safety check prevented self-connection:`, {
        userId,
        targetUserDocId
      });
      return res.status(400).json({
        success: false,
        message: 'Cannot connect to yourself'
      });
    }

    // Create connection with the actual document ID
    const connectionData = createConnection(userId, targetUserDocId, message);
    
    // If autoAccept is true (from invite link), set status to accepted
    if (autoAccept) {
      const now = new Date().toISOString();
      connectionData.status = 'accepted';
      connectionData.acceptedAt = now;
    }
    
    const errors = validateConnection(connectionData);
    
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Add to Firestore
    console.log(`💾 Creating connection with data:`, connectionData);
    const docRef = await db.collection(COLLECTIONS.CONNECTIONS).add(connectionData);
    const newDoc = await docRef.get();
    const connection = serializeDoc(newDoc);
    
    // Populate connected user data
    connection.connectedUser = serializeDoc(targetUserDoc);
    
    console.log(`✅ Connection created successfully:`, {
      connectionId: connection.id,
      userId: connection.userId,
      connectedUserId: connection.connectedUserId,
      status: connection.status
    });

    res.status(201).json({
      success: true,
      data: connection
    });

    // If auto-accepted, update user arrays immediately
    if (autoAccept) {
      try {
        console.log('🔄 Auto-accept flow: Updating user arrays for both users');
        
        const batch = db.batch();
        
        // Update requester's arrays
        const requesterRef = db.collection(COLLECTIONS.USERS).doc(userId);
        batch.update(requesterRef, {
          connections: FieldValue.arrayUnion(targetUserDocId),
          following: FieldValue.arrayUnion(targetUserDocId),
          followingCount: FieldValue.increment(1),
          followers: FieldValue.arrayUnion(targetUserDocId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        // Update target user's arrays
        const targetRef = db.collection(COLLECTIONS.USERS).doc(targetUserDocId);
        batch.update(targetRef, {
          connections: FieldValue.arrayUnion(userId),
          following: FieldValue.arrayUnion(userId),
          followingCount: FieldValue.increment(1),
          followers: FieldValue.arrayUnion(userId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        await batch.commit();
        console.log('✅ Auto-accept: User arrays updated successfully');
        
        // Send SSE notifications for the auto-accepted connection
        sseService.notifyUser(userId, 'connection_accepted', {
          connectionId: connection.id,
          acceptedBy: targetUserDocId
        });
        
        sseService.notifyUser(targetUserDocId, 'connection_accepted', {
          connectionId: connection.id,
          acceptedBy: userId
        });
        
      } catch (autoAcceptError) {
        console.error('❌ Error updating user arrays for auto-accept:', autoAcceptError);
        // Don't fail the request if array update fails
      }
    }

    // Send notification to target user if not auto-accepted
    if (!autoAccept) {
      try {
        await notificationService.notifyConnectionRequest(userId, targetUserDocId, connection.id);
        
        // Send real-time SSE notification
        sseService.notifyUser(targetUserDocId, 'connection_request', {
          connectionId: connection.id,
          from: connection.connectedUser,
          message: message || null
        });
        
        
      } catch (notifError) {
        console.error('Error sending connection request notification:', notifError);
        // Don't fail the request if notification fails
      }
    }

  } catch (error) {
    console.error('❌ Error sending connection request:', {
      error: error.message,
      stack: error.stack,
      userId: req.user?.uid,
      targetUserId: req.body?.targetUserId
    });
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Accept connection request
// @route   POST /api/connections/:id/accept
// @access  Private
const acceptConnection = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const connectionId = req.params.id;

    // Get connection document
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = connectionDoc.data();

    console.log(`🔍 Accept connection check:`, {
      connectionId: connectionId,
      userId: userId,
      connectedUserId: connection.connectedUserId,
      requestingUserId: connection.userId,
      normalizedCurrentUser: normalizeUserId(userId),
      normalizedConnectedUser: normalizeUserId(connection.connectedUserId)
    });

    // Check if user is the target of this connection request
    // Use the helper function to handle ID format differences
    if (!isSameUser(connection.connectedUserId, userId)) {
      console.log(`❌ User not authorized to accept connection:`, {
        expectedUserId: connection.connectedUserId,
        actualUserId: userId,
        normalized: {
          expected: normalizeUserId(connection.connectedUserId),
          actual: normalizeUserId(userId)
        }
      });
      return res.status(403).json({
        success: false,
        message: 'Not authorized to accept this connection'
      });
    }

    if (connection.status !== 'pending') {
      return res.status(400).json({
        success: false,
        message: 'Connection is not pending'
      });
    }

    // Update connection status
    const now = new Date().toISOString();
    await connectionDoc.ref.update({
      status: 'accepted',
      acceptedAt: now,
      updatedAt: now
    });

    // Get updated document
    const updatedDoc = await connectionDoc.ref.get();
    const updatedConnection = serializeDoc(updatedDoc);

    // Populate connected user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(connection.userId).get();
    if (userDoc.exists) {
      updatedConnection.connectedUser = serializeDoc(userDoc);
    }

    res.status(200).json({
      success: true,
      data: updatedConnection
    });

    // Auto-follow: When connection is accepted, both users automatically follow each other
    try {
      console.log('🔄 Auto-follow on connection accept - Making users follow each other');
      
      // Use a batch to update both users atomically
      const batch = db.batch();
      
      // User who accepted the connection follows the requester
      const acceptingUserRef = db.collection(COLLECTIONS.USERS).doc(userId);
      batch.update(acceptingUserRef, {
        following: FieldValue.arrayUnion(connection.userId),
        followingCount: FieldValue.increment(1),
        updatedAt: new Date().toISOString()
      });
      
      // Requester follows the user who accepted
      const requesterRef = db.collection(COLLECTIONS.USERS).doc(connection.userId);
      batch.update(requesterRef, {
        following: FieldValue.arrayUnion(userId),
        followingCount: FieldValue.increment(1),
        updatedAt: new Date().toISOString()
      });
      
      // Update followers arrays
      batch.update(acceptingUserRef, {
        followers: FieldValue.arrayUnion(connection.userId),
        followersCount: FieldValue.increment(1)
      });
      
      batch.update(requesterRef, {
        followers: FieldValue.arrayUnion(userId),
        followersCount: FieldValue.increment(1)
      });
      
      // Update connections arrays for both users
      batch.update(acceptingUserRef, {
        connections: FieldValue.arrayUnion(connection.userId)
      });
      
      batch.update(requesterRef, {
        connections: FieldValue.arrayUnion(userId)
      });
      
      await batch.commit();
      console.log('✅ Auto-follow successful - Both users now follow each other');
      console.log('✅ Connections arrays updated for both users');
      
      // Send SSE notifications for the follows
      sseService.notifyUser(userId, 'following_added', {
        targetUserId: connection.userId
      });
      
      sseService.notifyUser(connection.userId, 'following_added', {
        targetUserId: userId
      });
      
    } catch (followError) {
      console.error('❌ Error in auto-follow during connection accept:', followError);
      // Don't fail the connection accept if auto-follow fails
    }

    // Send notification to the requester that their connection was accepted
    try {
      const acceptingUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      const acceptingUserName = acceptingUserDoc.exists ? acceptingUserDoc.data().displayName : 'Someone';
      
      // Send push notification
      await notificationService.sendToUser(connection.userId, {
        type: 'connection_accepted',
        title: 'Connection Accepted',
        body: `${acceptingUserName} accepted your connection request`,
        data: {
          type: 'connection_accepted',
          acceptedByUserId: userId
        }
      });
      
      // Send real-time SSE notification
      sseService.notifyUser(connection.userId, 'connection_accepted', {
        connectionId: connectionId,
        acceptedBy: {
          id: userId,
          displayName: acceptingUserName
        }
      });
      
      // Send email notification
      const requesterDoc = await db.collection(COLLECTIONS.USERS).doc(connection.userId).get();
      if (requesterDoc.exists && requesterDoc.data().email) {
        const emailService = require('../services/emailService');
        await emailService.sendConnectionAcceptedEmail(
          requesterDoc.data().email,
          acceptingUserName
        );
      }
    } catch (notifError) {
      console.error('Error sending acceptance notification:', notifError);
      // Don't fail the request if notification fails
    }

  } catch (error) {
    console.error('Error accepting connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Decline connection request
// @route   DELETE /api/connections/:id/decline
// @access  Private
const declineConnection = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const connectionId = req.params.id;

    // Get connection document
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = connectionDoc.data();

    // Check if user is authorized to decline (either party can decline)
    // Use the helper function to handle ID format differences
    if (!isSameUser(connection.userId, userId) && !isSameUser(connection.connectedUserId, userId)) {
      console.log(`❌ User not authorized to decline connection:`, {
        connectionUserId: connection.userId,
        connectedUserId: connection.connectedUserId,
        currentUserId: userId,
        normalized: {
          connectionUser: normalizeUserId(connection.userId),
          connectedUser: normalizeUserId(connection.connectedUserId),
          currentUser: normalizeUserId(userId)
        }
      });
      return res.status(403).json({
        success: false,
        message: 'Not authorized to decline this connection'
      });
    }

    // Delete the connection request
    await connectionDoc.ref.delete();

    res.status(200).json({
      success: true,
      message: 'Connection request declined'
    });

    // Send SSE notification to the other party
    const otherUserId = isSameUser(connection.userId, userId) ? connection.connectedUserId : connection.userId;
    sseService.notifyUser(otherUserId, 'connection_declined', {
      connectionId: connectionId,
      declinedBy: userId
    });

  } catch (error) {
    console.error('Error declining connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Block connection
// @route   POST /api/connections/:id/block
// @access  Private
const blockConnection = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const connectionId = req.params.id;

    // Get connection document
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = connectionDoc.data();

    // Check if user is part of this connection
    // Use the helper function to handle ID format differences
    if (!isSameUser(connection.userId, userId) && !isSameUser(connection.connectedUserId, userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to block this connection'
      });
    }

    // Update connection status to blocked
    const now = new Date().toISOString();
    await connectionDoc.ref.update({
      status: 'blocked',
      updatedAt: now
    });

    // TODO: Revoke all shared circles between these users
    // This would be implemented as part of the circle sharing functionality

    res.status(200).json({
      success: true,
      message: 'Connection blocked successfully'
    });

  } catch (error) {
    console.error('Error blocking connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get shared circles with a connection
// @route   GET /api/connections/:id/shared-circles
// @access  Private
const getSharedCirclesWithConnection = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const connectionId = req.params.id;

    // Get connection to verify it exists and get the other user's ID
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = connectionDoc.data();
    
    // Verify user is part of this connection
    // Use the helper function to handle ID format differences
    if (!isSameUser(connection.userId, userId) && !isSameUser(connection.connectedUserId, userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this connection'
      });
    }

    // Get the other user's ID
    const otherUserId = isSameUser(connection.userId, userId) ? connection.connectedUserId : connection.userId;

    // Find circle shares between these users
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('sharedBy', '==', userId)
      .where('sharedWith', '==', otherUserId)
      .where('shareType', '==', 'registered_user')
      .get();

    // Get the circles that are shared
    const circleIds = sharesQuery.docs.map(doc => doc.data().circleId);
    
    if (circleIds.length === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Fetch circle details
    const circlePromises = circleIds.map(id => 
      db.collection(COLLECTIONS.CIRCLES).doc(id).get()
    );
    
    const circleDocs = await Promise.all(circlePromises);
    const circles = circleDocs
      .filter(doc => doc.exists)
      .map(doc => serializeDoc(doc));

    res.status(200).json({
      success: true,
      data: circles
    });

  } catch (error) {
    console.error('Error fetching shared circles with connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Remove/delete a connection
// @route   DELETE /api/connections/:id
// @access  Private
const removeConnection = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const connectionId = req.params.id;

    // Get connection document
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }

    const connection = connectionDoc.data();

    // Check if user is part of this connection
    // Use the helper function to handle ID format differences
    if (!isSameUser(connection.userId, userId) && !isSameUser(connection.connectedUserId, userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to remove this connection'
      });
    }

    // Remove from connections arrays and delete the connection
    try {
      const batch = db.batch();
      
      // Remove from both users' connections arrays
      const user1Ref = db.collection(COLLECTIONS.USERS).doc(connection.userId);
      batch.update(user1Ref, {
        connections: FieldValue.arrayRemove(connection.connectedUserId),
        updatedAt: new Date().toISOString()
      });
      
      const user2Ref = db.collection(COLLECTIONS.USERS).doc(connection.connectedUserId);
      batch.update(user2Ref, {
        connections: FieldValue.arrayRemove(connection.userId),
        updatedAt: new Date().toISOString()
      });
      
      // Delete the connection document
      batch.delete(connectionDoc.ref);
      
      await batch.commit();
      console.log('✅ Connection removed and user arrays updated');
    } catch (updateError) {
      console.error('❌ Error updating arrays during connection removal:', updateError);
      // Try to at least delete the connection document
      await connectionDoc.ref.delete();
    }

    res.status(200).json({
      success: true,
      message: 'Connection removed successfully'
    });

  } catch (error) {
    console.error('Error removing connection:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get connections sorted by weighted score
// @route   GET /api/connections/active
// @access  Private
const getActiveConnections = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const limit = parseInt(req.query.limit) || 10;
    const offset = parseInt(req.query.offset) || 0;
    
    console.log(`🔍 Getting active connections for user ${userId} with limit ${limit}, offset ${offset}`);
    
    // Get all accepted connections
    const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted');
      
    const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted');

    const [snapshot1, snapshot2] = await Promise.all([
      connectionsQuery1.get(),
      connectionsQuery2.get()
    ]);

    // Combine and deduplicate
    const allConnections = [...snapshot1.docs, ...snapshot2.docs];
    const uniqueConnections = allConnections.filter((doc, index, self) => 
      index === self.findIndex(d => d.id === doc.id)
    );

    // Process connections with all necessary data
    const connectionsWithScores = await Promise.all(
      uniqueConnections.map(async (doc) => {
        const connection = serializeDoc(doc);
        
        // Get the connected user
        const otherUserIdRaw = connection.userId === userId ? connection.connectedUserId : connection.userId;
        // Normalize the ID before looking up the user
        const otherUserId = normalizeUserId(otherUserIdRaw);
        
        try {
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(otherUserId).get();
          if (userDoc.exists) {
            connection.connectedUser = serializeDoc(userDoc);
            
            // Get total places count
            const userCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
              .where('owner', '==', otherUserId)
              .get();
            
            let totalPlaces = 0;
            for (const circleDoc of userCirclesSnapshot.docs) {
              const circleData = circleDoc.data();
              totalPlaces += (circleData.places || []).length;
            }
            
            // Check for unviewed activities AND calculate total activity
            const recentActivity = connection.recentActivity || [];
            const hasUnviewedActivity = recentActivity.length > 0 && recentActivity.some(activity => {
              const viewedBy = activity.viewedBy || [];
              return !viewedBy.includes(userId);
            });
            
            // Calculate total activity count (viewed + unviewed) for highly active user detection
            const totalActivityCount = recentActivity.length;
            const unviewedActivityCount = recentActivity.filter(activity => {
              const viewedBy = activity.viewedBy || [];
              return !viewedBy.includes(userId);
            }).length;
            
            // Get last message info for this connection (THIS WAS MISSING!)
            let lastMessageAt = null;
            let lastMessageSenderId = null;
            let hasRecentMessage = false;
            
            // Find conversations between current user and connected user
            const conversationQuery = db.collection(COLLECTIONS.CONVERSATIONS)
              .where('type', '==', 'direct')
              .where('participants', 'array-contains', userId);
              
            const conversationSnapshot = await conversationQuery.get();
            
            // Filter to find conversation with this specific connected user
            const conversation = conversationSnapshot.docs.find(doc => {
              const data = doc.data();
              return data.participants.includes(otherUserId);
            });
            
            if (conversation) {
              const convData = conversation.data();
              if (convData.lastMessageTime) {
                lastMessageAt = convData.lastMessageTime;
                lastMessageSenderId = convData.lastMessageSenderId || null;
                
                // Check if message is recent (within last 7 days)
                const messageDate = new Date(convData.lastMessageTime);
                const sevenDaysAgo = new Date();
                sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
                hasRecentMessage = messageDate > sevenDaysAgo;
              }
            }
            
            // Add stats - FIXED: Only set hasRecentPlace/hasNewActivity if there's actual unviewed content
            connection.totalPlaces = totalPlaces;
            connection.hasRecentPlace = hasUnviewedActivity && unviewedActivityCount > 0;
            connection.hasNewActivity = hasUnviewedActivity && unviewedActivityCount > 0;
            connection.viewCount = connection.viewCount || 0;
            connection.lastMessageAt = lastMessageAt;
            connection.lastMessageSenderId = lastMessageSenderId;
            connection.hasRecentMessage = hasRecentMessage;
            
            // Add total activity tracking for highly active users
            connection.totalActivityCount = totalActivityCount;
            connection.unviewedActivityCount = unviewedActivityCount;
            
            // Calculate score
            const scoreData = scoringService.calculateConnectionScore(connection, userId);
            connection.connectionScore = scoreData.score;
            connection.scoreComponents = scoreData.components;
            connection.scoreLastCalculated = scoreData.calculatedAt;
            
            // Score calculated for connection
            
            // Score processing completed
          }
        } catch (error) {
          console.error(`Error processing connection ${doc.id}:`, error);
        }
        
        return connection;
      })
    );

    // Filter valid connections and sort by score
    const validConnections = connectionsWithScores
      .filter(conn => conn.connectedUser && conn.connectionScore !== undefined)
      .sort((a, b) => b.connectionScore - a.connectionScore);

    // 🔍 DEBUG: Log all connections with scores to debug Dan Wickner ordering
    console.log('🔍 DEBUG: All connections with scores (before limit):');
    validConnections.forEach((conn, index) => {
      const name = conn.connectedUser?.displayName || 'Unknown';
      const score = conn.connectionScore || 0;
      const components = conn.scoreComponents;
      const hasMessages = conn.lastMessageAt ? '✓' : '✗';
      const hasActivity = conn.hasRecentPlace ? '✓' : '✗';
      const messageAge = conn.lastMessageAt ? Math.round((Date.now() - new Date(conn.lastMessageAt).getTime()) / (1000 * 60 * 60 * 24)) + 'd' : 'none';
      
      console.log(`   ${index + 1}. ${name} | Score: ${score} | Messages: ${hasMessages} (${messageAge}) | Activity: ${hasActivity} | Places: ${conn.totalPlaces || 0} | Views: ${conn.viewCount || 0} | TotalActivity: ${conn.totalActivityCount || 0}`);
      
      if (components) {
        console.log(`      Components: M:${components.messages} E:${components.engagement} C:${components.content} R:${components.recency} = ${components.total}`);
      }
    });

    // Apply pagination with offset
    const finalConnections = validConnections.slice(offset, offset + limit);
    
    // Log final order
    console.log(`🔍 DEBUG: Returning connections ${offset + 1}-${offset + finalConnections.length} out of ${validConnections.length} total:`);
    finalConnections.forEach((conn, index) => {
      const name = conn.connectedUser?.displayName || 'Unknown';
      console.log(`   ${offset + index + 1}. ${name} (Score: ${conn.connectionScore})`);
    });

    // Returning connections sorted by score
    
    res.status(200).json({
      success: true,
      connections: finalConnections,
      pagination: {
        offset: offset,
        limit: limit,
        total: validConnections.length,
        hasMore: offset + limit < validConnections.length
      }
    });
  } catch (error) {
    console.error('Error fetching active connections:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Clear activity notification for a connection
// @route   POST /api/connections/:id/clear-activity
// @access  Private
const clearConnectionActivity = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const { id: connectionId } = req.params;
    
    // Get the connection to find the connected user
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }
    
    const connection = connectionDoc.data();
    const connectedUserId = isSameUser(connection.userId, userId) ? connection.connectedUserId : connection.userId;
    
    await activityService.clearActivityNotification(userId, connectedUserId);
    
    res.status(200).json({
      success: true,
      message: 'Activity notification cleared'
    });
  } catch (error) {
    console.error('Error clearing activity notification:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Track connection view
// @route   POST /api/connections/:id/track-view
// @access  Private
const trackConnectionView = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const { id: connectionId } = req.params;
    
    // Get the connection to find the connected user
    const connectionDoc = await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).get();
    
    if (!connectionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Connection not found'
      });
    }
    
    const connection = connectionDoc.data();
    const connectedUserId = isSameUser(connection.userId, userId) ? connection.connectedUserId : connection.userId;
    
    await activityService.trackConnectionView(userId, connectedUserId);
    
    res.status(200).json({
      success: true,
      message: 'View tracked'
    });
  } catch (error) {
    console.error('Error tracking connection view:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get active connections and followed users combined
// @route   GET /api/connections/active-relationships
// @access  Private
const getActiveRelationships = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    const limit = parseInt(req.query.limit) || 10;
    const offset = parseInt(req.query.offset) || 0;
    
    console.log(`🔍 Getting active relationships (connections + following) for user ${userId} with limit ${limit}, offset ${offset}`);
    
    // Get all accepted connections (same as before)
    const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted');
      
    const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted');

    // Get users this person is following
    console.log(`🔍 Looking up user document for: ${userId}`);
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    
    if (!userDoc.exists) {
      console.log(`⚠️ User document not found for: ${userId}`);
    }
    
    const userData = userDoc.exists ? userDoc.data() : null;
    const followingIds = userData?.following || [];
    
    console.log(`📊 User ${userId} is following ${followingIds.length} users`);
    if (followingIds.length > 0) {
      console.log(`📊 Following IDs: ${followingIds.join(', ')}`);
    }

    const [snapshot1, snapshot2] = await Promise.all([
      connectionsQuery1.get(),
      connectionsQuery2.get()
    ]);

    // Process connections
    const connectionDocs = [...snapshot1.docs, ...snapshot2.docs];
    const connectionMap = new Map();
    
    for (const doc of connectionDocs) {
      const data = doc.data();
      const otherUserId = data.userId === userId ? data.connectedUserId : data.userId;
      
      if (!connectionMap.has(otherUserId)) {
        connectionMap.set(otherUserId, {
          id: doc.id,
          ...data,
          relationshipType: 'connection'
        });
      }
    }

    // Now get followed users that are NOT connections
    const followedOnlyIds = followingIds.filter(id => !connectionMap.has(id));
    console.log(`📊 ${followedOnlyIds.length} followed users are not connections`);

    // Fetch user data for all relationships
    const allUserIds = [...Array.from(connectionMap.keys()), ...followedOnlyIds];
    
    if (allUserIds.length === 0) {
      return res.status(200).json({
        success: true,
        relationships: [],
        total: 0
      });
    }

    // Get user data for all relationships
    const userPromises = allUserIds.map(id => 
      db.collection(COLLECTIONS.USERS).doc(id).get()
    );
    const userDocs = await Promise.all(userPromises);
    const userDataMap = new Map();
    
    userDocs.forEach(doc => {
      if (doc.exists) {
        userDataMap.set(doc.id, {
          id: doc.id,
          ...doc.data()
        });
      }
    });

    // Build relationships array with both connections and followed users
    const relationships = [];
    
    // Add connections
    for (const [otherUserId, connectionData] of connectionMap) {
      const userData = userDataMap.get(otherUserId);
      if (userData) {
        // Calculate activity score for connection
        const scoreData = scoringService.calculateConnectionScore(connectionData, userId);
        
        relationships.push({
          ...connectionData,
          connectedUser: userData,
          relationshipType: 'connection',
          connectionScore: scoreData.score,
          scoreComponents: scoreData.components,
          hasRecentPlace: scoreData.hasRecentPlace,
          lastMessageAt: scoreData.lastMessageAt,
          totalPlaces: scoreData.totalPlaces
        });
      }
    }

    // Add followed-only users
    for (const followedId of followedOnlyIds) {
      const userData = userDataMap.get(followedId);
      if (userData) {
        // Calculate activity score for followed user
        const recentPlaceSnapshot = await db.collection(COLLECTIONS.PLACES)
          .where('addedBy', '==', followedId)
          .where('createdAt', '>', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000))
          .limit(1)
          .get();
        
        const hasRecentPlace = !recentPlaceSnapshot.empty;
        
        // Get total places count
        const totalPlacesSnapshot = await db.collection(COLLECTIONS.PLACES)
          .where('addedBy', '==', followedId)
          .count()
          .get();
        
        const totalPlaces = totalPlacesSnapshot.data().count || 0;
        
        // FIXED: More balanced scoring for followed users (not inflated)
        // Base score on actual activity, not just existence of places
        let score = 0;
        if (hasRecentPlace) {
          score = 30; // Recent activity gets 30 points
        }
        if (totalPlaces > 10) {
          score += 15; // Active user bonus
        } else if (totalPlaces > 5) {
          score += 10; // Moderate activity
        } else if (totalPlaces > 0) {
          score += 5; // Some activity
        }
        
        relationships.push({
          id: `follow_${followedId}`, // Synthetic ID for followed relationships
          userId: userId,
          connectedUserId: followedId,
          connectedUser: userData,
          relationshipType: 'following',
          status: 'following', // Not a connection status, but indicates following
          connectionScore: score,
          hasRecentPlace: hasRecentPlace,
          totalPlaces: totalPlaces,
          createdAt: userData.createdAt || new Date()
        });
      }
    }

    // Sort all relationships by score
    relationships.sort((a, b) => {
      const scoreA = a.connectionScore || 0;
      const scoreB = b.connectionScore || 0;
      return scoreB - scoreA;
    });

    // Apply pagination
    const paginatedRelationships = relationships.slice(offset, offset + limit);
    
    console.log(`✅ Returning ${paginatedRelationships.length} active relationships (${relationships.length} total)`);
    console.log(`   - Connections: ${relationships.filter(r => r.relationshipType === 'connection').length}`);
    console.log(`   - Following: ${relationships.filter(r => r.relationshipType === 'following').length}`);

    res.status(200).json({
      success: true,
      relationships: paginatedRelationships,
      total: relationships.length
    });

  } catch (error) {
    console.error('Error getting active relationships:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  getConnections,
  getConnectionById,
  sendConnectionRequest,
  acceptConnection,
  declineConnection,
  blockConnection,
  getSharedCirclesWithConnection,
  removeConnection,
  getActiveConnections,
  getActiveRelationships,
  clearConnectionActivity,
  trackConnectionView
};