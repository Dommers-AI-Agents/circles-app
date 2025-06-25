// backend/controllers/connectionController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createConnection, 
  validateConnection, 
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get user connections
// @route   GET /api/connections
// @access  Private
const getConnections = async (req, res) => {
  try {
    const userId = req.user.uid;

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

    // Serialize and populate user data
    const connections = await Promise.all(
      uniqueConnections.map(async (doc) => {
        const connection = serializeDoc(doc);
        
        // Determine which user is the "other" user
        const otherUserId = connection.userId === userId ? connection.connectedUserId : connection.userId;
        
        // Fetch the other user's data
        try {
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(otherUserId).get();
          if (userDoc.exists) {
            connection.connectedUser = serializeDoc(userDoc);
            connection.connectedUserId = otherUserId;
          }
        } catch (error) {
          console.error(`Error fetching user ${otherUserId}:`, error);
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
    const userId = req.user.uid;
    const { targetUserId, message, autoAccept } = req.body;
    
    console.log(`Connection request from userId: ${userId} to targetUserId: ${targetUserId}`);

    // Validate input
    if (!targetUserId) {
      return res.status(400).json({
        success: false,
        message: 'Target user ID is required'
      });
    }

    if (targetUserId === userId) {
      return res.status(400).json({
        success: false,
        message: 'Cannot connect to yourself'
      });
    }

    // Check if target user exists
    console.log(`Checking if target user exists with ID: ${targetUserId}`);
    const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
    if (!targetUserDoc.exists) {
      console.error(`Target user not found with ID: ${targetUserId}`);
      return res.status(404).json({
        success: false,
        message: 'Target user not found',
        targetUserId: targetUserId
      });
    }
    console.log(`Target user found: ${targetUserDoc.data().displayName || 'No name'}`)

    // Check if connection already exists
    const existingConnectionQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('connectedUserId', '==', targetUserId)
      .get();

    const existingConnectionQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', targetUserId)
      .where('connectedUserId', '==', userId)
      .get();

    if (!existingConnectionQuery1.empty || !existingConnectionQuery2.empty) {
      // If connection exists and is already accepted, return success
      const existingConnection = !existingConnectionQuery1.empty ? 
        existingConnectionQuery1.docs[0] : existingConnectionQuery2.docs[0];
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
      
      return res.status(409).json({
        success: false,
        message: 'Connection request already pending'
      });
    }

    // Create connection
    const connectionData = createConnection(userId, targetUserId, message);
    
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
    const docRef = await db.collection(COLLECTIONS.CONNECTIONS).add(connectionData);
    const newDoc = await docRef.get();
    const connection = serializeDoc(newDoc);
    
    // Populate connected user data
    connection.connectedUser = serializeDoc(targetUserDoc);

    res.status(201).json({
      success: true,
      data: connection
    });

  } catch (error) {
    console.error('Error sending connection request:', error);
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
    const userId = req.user.uid;
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

    // Check if user is the target of this connection request
    if (connection.connectedUserId !== userId) {
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
    const userId = req.user.uid;
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
    if (connection.userId !== userId && connection.connectedUserId !== userId) {
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
    const userId = req.user.uid;
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
    if (connection.userId !== userId && connection.connectedUserId !== userId) {
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
    const userId = req.user.uid;
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
    if (connection.userId !== userId && connection.connectedUserId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this connection'
      });
    }

    // Get the other user's ID
    const otherUserId = connection.userId === userId ? connection.connectedUserId : connection.userId;

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

module.exports = {
  getConnections,
  sendConnectionRequest,
  acceptConnection,
  declineConnection,
  blockConnection,
  getSharedCirclesWithConnection
};