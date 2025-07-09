// backend/controllers/connectionController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createConnection, 
  validateConnection, 
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const activityService = require('../services/activityService');
const notificationService = require('../services/notificationService');

const db = getFirestore();

// Helper function to normalize user IDs for comparison
// Handles both simple format (e.g., "9b5eeac93282416c9bc6dcecbc49b40f") 
// and complex format (e.g., "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127")
const normalizeUserId = (userId) => {
  if (!userId) return userId;
  
  // If it's a complex format, extract the middle part
  if (userId.includes('.')) {
    const parts = userId.split('.');
    if (parts.length >= 2) {
      return parts[1]; // Return the simple ID
    }
  }
  
  // Otherwise return as-is (already simple format)
  return userId;
};

// Helper function to check if two user IDs are the same (accounting for format differences)
const isSameUser = (userId1, userId2) => {
  if (!userId1 || !userId2) return false;
  
  const normalized1 = normalizeUserId(userId1);
  const normalized2 = normalizeUserId(userId2);
  
  return normalized1 === normalized2;
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
        const otherUserId = connection.userId === userId ? connection.connectedUserId : connection.userId;
        
        // Fetch the other user's data
        try {
          console.log(`🔍 Fetching connected user data for ID: ${otherUserId}`);
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
            
            // Check if user recently added a place (within last 7 days)
            // ALWAYS calculate from recentActivity array, never use persisted value
            const sevenDaysAgo = new Date();
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
            
            // Ensure we have recentActivity array and calculate dynamically
            const recentActivity = connection.recentActivity || [];
            const calculatedHasRecentPlace = recentActivity.some(activity => 
              activity.type === 'place' && 
              new Date(activity.createdAt) > sevenDaysAgo
            );
            
            // Add stats to connection - ALWAYS override with calculated value
            connection.totalPlaces = totalPlaces;
            connection.hasRecentPlace = calculatedHasRecentPlace; // Always use calculated value
            
            // Log for debugging
            if (connection.hasRecentPlace !== calculatedHasRecentPlace) {
              console.log(`🔧 Overriding persisted hasRecentPlace (${connection.hasRecentPlace}) with calculated value (${calculatedHasRecentPlace}) for connection ${connection.id}`);
            }
            connection.viewCount = connection.viewCount || 0;
            
            console.log(`📊 Stats for ${connection.connectedUser.displayName}: Places=${totalPlaces}, Views=${connection.viewCount}, Recent=${calculatedHasRecentPlace}`);
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

    // Parse target user ID if it's in complex format
    let actualTargetUserId = targetUserId;
    if (targetUserId.includes('.')) {
      const parts = targetUserId.split('.');
      if (parts.length >= 2) {
        actualTargetUserId = parts[1]; // Use the middle part as Firebase UID
        console.log(`🔄 Parsed complex target user ID from ${targetUserId} to ${actualTargetUserId}`);
      }
    } else {
      // Simple format - use as is
      console.log(`✅ Using simple target user ID as-is: ${actualTargetUserId}`);
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

    // Send notification to target user if not auto-accepted
    if (!autoAccept) {
      try {
        await notificationService.notifyConnectionRequest(userId, targetUserDocId);
        
        // Also create a system message in the user's inbox
        const senderDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
        const senderName = senderDoc.exists ? senderDoc.data().displayName : 'Someone';
        
        // Create or find direct conversation between users
        let directConversation = null;
        
        // Check if a direct conversation already exists
        const existingConvQuery = await db.collection(COLLECTIONS.CONVERSATIONS)
          .where('type', '==', 'direct')
          .where('participants', 'array-contains', userId)
          .get();
          
        const existingConversation = existingConvQuery.docs.find(doc => {
          const data = doc.data();
          return data.participants.includes(targetUserDocId) && 
                 data.participants.length === 2;
        });
        
        if (existingConversation) {
          directConversation = { id: existingConversation.id, ...existingConversation.data() };
        } else {
          // Create direct conversation
          const { createConversation } = require('../models/FirestoreModels');
          const convData = createConversation({
            type: 'direct',
            participants: [userId, targetUserDocId],
            name: null,
            avatar: null
          }, userId);
          
          const convRef = await db.collection(COLLECTIONS.CONVERSATIONS).add(convData);
          directConversation = { id: convRef.id, ...convData };
        }
        
        // Create connection request message
        const { createMessage } = require('../models/FirestoreModels');
        const messageData = createMessage({
          type: 'connection_request',
          content: `${senderName} wants to connect with you`,
          metadata: {
            connectionId: docRef.id,
            senderId: userId,
            senderName: senderName,
            senderAvatar: senderDoc.exists ? senderDoc.data().profilePicture : null,
            status: 'pending' // Track if this request has been handled
          }
        }, directConversation.id, userId);
        
        await db.collection(COLLECTIONS.MESSAGES).add(messageData);
        
        // Update conversation's last message time
        await db.collection(COLLECTIONS.CONVERSATIONS).doc(directConversation.id).update({
          lastMessageTime: messageData.createdAt,
          lastMessage: messageData.content,
          lastMessageType: 'connection_request'
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

    // Delete the connection
    await connectionDoc.ref.delete();

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

// @desc    Get connections sorted by activity and stats
// @route   GET /api/connections/active
// @access  Private
const getActiveConnections = async (req, res) => {
  try {
    const userId = req.user.firebaseDocId || req.user.uid;
    
    const connections = await activityService.getConnectionsWithStats(userId);
    
    res.status(200).json({
      success: true,
      connections: connections
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

module.exports = {
  getConnections,
  sendConnectionRequest,
  acceptConnection,
  declineConnection,
  blockConnection,
  getSharedCirclesWithConnection,
  removeConnection,
  getActiveConnections,
  clearConnectionActivity,
  trackConnectionView
};