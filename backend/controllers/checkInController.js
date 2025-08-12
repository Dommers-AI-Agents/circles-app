// backend/controllers/checkInController.js
const { getFirestore, FieldValue, GeoPoint } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCheckIn, 
  createPlace,
  validateCheckIn,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { createActivity } = require('./activityController');
const notificationService = require('../services/notificationService');
const sseService = require('../services/sseService');

const db = getFirestore();

// Create a new check-in
exports.createCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInData = req.body;
    
    // Get user data for check-in
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    const userData = userDoc.data();
    
    // Create check-in object
    const checkIn = createCheckIn(checkInData, userId, userData);
    
    // Convert coordinates to GeoPoint if provided
    if (checkInData.latitude && checkInData.longitude) {
      checkIn.location = new GeoPoint(checkInData.latitude, checkInData.longitude);
    }
    
    // Validate check-in data
    const errors = validateCheckIn(checkInData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Save to Firestore
    const checkInRef = await db.collection(COLLECTIONS.CHECK_INS).add(checkIn);
    const checkInDoc = await checkInRef.get();
    const checkInId = checkInRef.id;
    
    // Send notifications to selected groups
    for (const groupId of checkIn.notifiedGroups) {
      // Create a special check-in message in the group
      const messageData = {
        type: 'check_in',
        content: `${userData.displayName} checked in at ${checkIn.placeName}`,
        metadata: {
          checkInId: checkInId,
          placeName: checkIn.placeName,
          placeAddress: checkIn.placeAddress,
          duration: checkIn.duration,
          message: checkIn.message,
          endTime: checkIn.endTime
        }
      };
      
      // Add message to conversation
      const messageRef = await db.collection(COLLECTIONS.MESSAGES).add({
        conversationId: groupId,
        senderId: userId,
        ...messageData,
        createdAt: new Date().toISOString()
      });
      
      // Update conversation's last message
      await db.collection(COLLECTIONS.CONVERSATIONS).doc(groupId).update({
        lastMessage: messageData.content,
        lastMessageTime: new Date().toISOString(),
        lastMessageSenderId: userId,
        updatedAt: new Date().toISOString()
      });
    }
    
    // Send notifications to individual users
    console.log(`📍 Sending check-in notifications to ${checkIn.notifiedUsers.length} users`);
    for (const notifiedUserId of checkIn.notifiedUsers) {
      console.log(`📍 Sending check-in notification to user: ${notifiedUserId}`);
      try {
        const result = await notificationService.sendToUser(notifiedUserId, {
          type: 'check_in',
          title: 'Check-in Notification',
          body: `${userData.displayName} is at ${checkIn.placeName}${checkIn.message ? ': ' + checkIn.message : ''}`,
          data: {
            checkInId: checkInId,
            placeName: checkIn.placeName,
            userId: userId
          }
        });
        console.log(`📍 Check-in notification result for ${notifiedUserId}:`, result);
      } catch (error) {
        console.error(`📍 Failed to send check-in notification to ${notifiedUserId}:`, error);
      }
    }
    
    // Add to activity feed if enabled
    if (checkIn.showInActivityFeed) {
      // Ensure place exists in database for all check-ins
      let finalPlaceId = checkIn.placeId;
      let placePhoto = null;
      
      if (checkIn.placeId) {
        // Check if place exists in database
        try {
          const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(checkIn.placeId).get();
          if (placeDoc.exists) {
            const placeData = placeDoc.data();
            if (placeData.photos && placeData.photos.length > 0) {
              placePhoto = placeData.photos[0];
            }
          } else {
            // Place ID provided but doesn't exist - clear it to create new
            finalPlaceId = null;
          }
        } catch (error) {
          console.error('Error fetching existing place for activity:', error);
          finalPlaceId = null;
        }
      }
      
      // If no valid place ID, create a new place from check-in data
      if (!finalPlaceId) {
        try {
          // First check if a place with same name and address already exists
          const existingPlacesQuery = await db.collection(COLLECTIONS.PLACES)
            .where('name', '==', checkIn.placeName)
            .where('address', '==', checkIn.placeAddress)
            .where('deletedAt', '==', null) // Only active places
            .limit(1)
            .get();
          
          if (!existingPlacesQuery.empty) {
            // Use existing place
            finalPlaceId = existingPlacesQuery.docs[0].id;
            const existingPlace = existingPlacesQuery.docs[0].data();
            if (existingPlace.photos && existingPlace.photos.length > 0) {
              placePhoto = existingPlace.photos[0];
            }
            console.log(`✅ Using existing place for check-in: ${checkIn.placeName} (ID: ${finalPlaceId})`);
          } else {
            // Create new place from check-in information
            const placeData = {
              name: checkIn.placeName,
              address: checkIn.placeAddress,
              location: checkIn.location ? {
                coordinates: [checkIn.location.longitude, checkIn.location.latitude]
              } : null,
              category: checkIn.placeCategory || 'other',
              // Mark this place as created from check-in
              addedViaCheckIn: true,
              photos: [] // Could add photos from check-in if available
            };
            
            // Create the place document
            const place = createPlace(placeData, null, userId); // circleId = null for floating places
            const placeRef = await db.collection(COLLECTIONS.PLACES).add(place);
            finalPlaceId = placeRef.id;
            
            console.log(`✅ Created new place from check-in: ${checkIn.placeName} (ID: ${finalPlaceId})`);
          }
        } catch (error) {
          console.error('Error creating place from check-in:', error);
          // Continue without place ID if creation fails
        }
      }
      
      await createActivity(
        'check_in',
        userId,
        'check_in',
        checkInId,
        checkIn.placeName,
        {
          placeAddress: checkIn.placeAddress,
          message: checkIn.message,
          endTime: checkIn.endTime,
          circleId: checkIn.circleId,
          circleName: null, // Could fetch circle name if needed
          placePhoto: placePhoto,
          placeId: finalPlaceId, // Use the guaranteed place ID
          latitude: checkIn.location ? checkIn.location.latitude : null,
          longitude: checkIn.location ? checkIn.location.longitude : null,
          placeCategory: checkIn.placeCategory || 'other'
        }
      );
    }
    
    // Send real-time updates
    sseService.notifyUser(userId, 'check_in_created', serializeDoc(checkInDoc));
    
    res.status(201).json({
      success: true,
      data: serializeDoc(checkInDoc)
    });
  } catch (error) {
    console.error('Error creating check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create check-in',
      error: error.message
    });
  }
};

// Get active check-ins visible to user
exports.getActiveCheckIns = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();
    
    // Get user's connections
    const [connections1, connections2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const connectionIds = new Set([userId]); // Include self
    connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
    
    // Get active check-ins from connections
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    // Filter check-ins based on visibility
    const visibleCheckIns = [];
    for (const doc of checkInsQuery.docs) {
      const checkIn = doc.data();
      
      // Check if user should see this check-in
      const isOwner = checkIn.userId === userId;
      const isNotified = checkIn.notifiedUsers.includes(userId);
      const isInNotifiedGroup = await isUserInAnyGroup(userId, checkIn.notifiedGroups);
      const isConnection = connectionIds.has(checkIn.userId) && checkIn.showInActivityFeed;
      
      if (isOwner || isNotified || isInNotifiedGroup || isConnection) {
        visibleCheckIns.push(serializeDoc(doc));
      }
    }
    
    res.json({
      success: true,
      data: visibleCheckIns
    });
  } catch (error) {
    console.error('Error getting active check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get active check-ins',
      error: error.message
    });
  }
};

// Get user's own active check-ins
exports.getMyActiveCheckIns = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();
    
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('userId', '==', userId)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    const checkIns = serializeQuerySnapshot(checkInsQuery);
    
    res.json({
      success: true,
      data: checkIns
    });
  } catch (error) {
    console.error('Error getting my check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get check-ins',
      error: error.message
    });
  }
};

// Respond to a check-in (interested/going)
exports.respondToCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInId = req.params.checkInId;
    const { status } = req.body; // 'interested' or 'going'
    
    if (!['interested', 'going'].includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status. Must be "interested" or "going"'
      });
    }
    
    const checkInRef = db.collection(COLLECTIONS.CHECK_INS).doc(checkInId);
    const checkInDoc = await checkInRef.get();
    
    if (!checkInDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Check-in not found'
      });
    }
    
    const checkIn = checkInDoc.data();
    
    // Verify check-in is still active
    if (!checkIn.active || new Date(checkIn.endTime) < new Date()) {
      return res.status(400).json({
        success: false,
        message: 'Check-in has ended'
      });
    }
    
    // Get user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userData = userDoc.data();
    
    // Update responses array
    const responses = checkIn.responses || [];
    const existingIndex = responses.findIndex(r => r.userId === userId);
    
    const responseData = {
      userId: userId,
      userName: userData.displayName || userData.firstName || 'User',
      userPhoto: userData.profilePicture || null,
      status: status,
      timestamp: new Date().toISOString()
    };
    
    if (existingIndex >= 0) {
      responses[existingIndex] = responseData;
    } else {
      responses.push(responseData);
    }
    
    await checkInRef.update({
      responses: responses,
      updatedAt: new Date().toISOString()
    });
    
    // Notify check-in owner
    if (checkIn.userId !== userId) {
      await notificationService.sendToUser(checkIn.userId, {
        type: 'check_in_response',
        title: 'Check-in Response',
        body: `${userData.displayName} is ${status === 'going' ? 'going to' : 'interested in'} ${checkIn.placeName}`,
        data: {
          checkInId: checkInId,
          responderId: userId,
          status: status
        }
      });
    }
    
    // Send real-time updates
    sseService.notifyUser(checkIn.userId, 'check_in_response', responseData);
    
    const updatedDoc = await checkInRef.get();
    
    res.json({
      success: true,
      data: serializeDoc(updatedDoc)
    });
  } catch (error) {
    console.error('Error responding to check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to respond to check-in',
      error: error.message
    });
  }
};

// End check-in early
exports.endCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInId = req.params.checkInId;
    
    const checkInRef = db.collection(COLLECTIONS.CHECK_INS).doc(checkInId);
    const checkInDoc = await checkInRef.get();
    
    if (!checkInDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Check-in not found'
      });
    }
    
    const checkIn = checkInDoc.data();
    
    // Verify ownership
    if (checkIn.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized to end this check-in'
      });
    }
    
    // Update check-in
    await checkInRef.update({
      active: false,
      endTime: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Send real-time updates
    sseService.notifyUser(userId, 'check_in_ended', { checkInId: checkInId });
    
    res.json({
      success: true,
      message: 'Check-in ended successfully'
    });
  } catch (error) {
    console.error('Error ending check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to end check-in',
      error: error.message
    });
  }
};

// Get check-ins at a specific place
exports.getCheckInsAtPlace = async (req, res) => {
  try {
    const placeId = req.params.placeId;
    const now = new Date();
    
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('placeId', '==', placeId)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    const checkIns = serializeQuerySnapshot(checkInsQuery);
    
    res.json({
      success: true,
      data: checkIns,
      count: checkIns.length
    });
  } catch (error) {
    console.error('Error getting check-ins at place:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get check-ins at place',
      error: error.message
    });
  }
};

// Helper function to check if user is in any of the notified groups
async function isUserInAnyGroup(userId, groupIds) {
  if (!groupIds || groupIds.length === 0) return false;
  
  for (const groupId of groupIds) {
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(groupId).get();
    if (conversationDoc.exists) {
      const conversation = conversationDoc.data();
      if (conversation.participants && conversation.participants.includes(userId)) {
        return true;
      }
    }
  }
  
  return false;
}

// Clean up expired check-ins (to be called by a cron job)
exports.cleanupExpiredCheckIns = async (req, res) => {
  try {
    const now = new Date();
    
    const expiredQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('active', '==', true)
      .where('endTime', '<=', now.toISOString())
      .get();
    
    const batch = db.batch();
    let count = 0;
    
    expiredQuery.docs.forEach(doc => {
      batch.update(doc.ref, {
        active: false,
        updatedAt: now.toISOString()
      });
      count++;
    });
    
    if (count > 0) {
      await batch.commit();
    }
    
    res.json({
      success: true,
      message: `Cleaned up ${count} expired check-ins`
    });
  } catch (error) {
    console.error('Error cleaning up check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cleanup check-ins',
      error: error.message
    });
  }
};