// backend/controllers/checkInController.js
const { getFirestore, FieldValue, GeoPoint } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCheckIn, 
  createPlace,
  createCircle,
  validateCheckIn,
  createNotification,
  validateNotification,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { createActivity } = require('./activityController');
const notificationService = require('../services/notificationService');
const sseService = require('../services/sseService');
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');

const db = getFirestore();
const googleMapsClient = new Client({});

// Helper function to find or create user's check-in circle
async function findOrCreateCheckInCircle(userId) {
  try {
    // Look for existing check-in circle
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .where('isCheckInCircle', '==', true)
      .limit(1)
      .get();
    
    if (!circlesSnapshot.empty) {
      // Return existing check-in circle
      return serializeDoc(circlesSnapshot.docs[0]);
    }
    
    // Create new check-in circle
    const checkInCircleData = {
      name: 'Check-in Places',
      description: 'Places I\'ve checked into',
      privacy: 'public', // Public by default for discovery
      isCheckInCircle: true,
      icon: '📍',
      color: '#4CAF50'
    };
    
    const circle = createCircle(checkInCircleData, userId);
    const circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circle);
    const circleDoc = await circleRef.get();
    
    console.log(`✅ Created Check-in Places circle for user ${userId}`);
    return serializeDoc(circleDoc);
  } catch (error) {
    console.error('Error finding/creating check-in circle:', error);
    throw error;
  }
}

// Helper function to enrich place data with Google Places API
async function enrichPlaceWithGoogleData(placeName, location) {
  try {
    if (!googleMapsApiKey) {
      console.warn('Google Maps API key not configured, skipping enrichment');
      return {};
    }
    
    // Search for the place using name and location
    const searchQuery = placeName;
    const searchLocation = location ? `${location.latitude},${location.longitude}` : null;
    
    // First try to find the place
    const searchResponse = await googleMapsClient.findPlaceFromText({
      params: {
        input: searchQuery,
        inputtype: 'textquery',
        fields: ['place_id', 'name', 'formatted_address', 'photos', 'types', 'rating', 'price_level'],
        locationbias: searchLocation ? `circle:1000@${searchLocation}` : undefined,
        key: googleMapsApiKey
      }
    });
    
    if (!searchResponse.data.candidates || searchResponse.data.candidates.length === 0) {
      console.log(`No Google Places results found for: ${placeName}`);
      return {};
    }
    
    const candidate = searchResponse.data.candidates[0];
    const placeId = candidate.place_id;
    
    // Get detailed place information
    const detailsResponse = await googleMapsClient.placeDetails({
      params: {
        place_id: placeId,
        fields: ['name', 'formatted_address', 'photos', 'types', 'rating', 'price_level', 'website', 'formatted_phone_number', 'opening_hours'],
        // Pin to English so weekday_text day names match the dayIndex map below
        language: 'en',
        key: googleMapsApiKey
      }
    });
    
    const placeDetails = detailsResponse.data.result;
    
    // Format photos array
    const photos = [];
    if (placeDetails.photos && placeDetails.photos.length > 0) {
      // Get up to 3 photos
      for (let i = 0; i < Math.min(3, placeDetails.photos.length); i++) {
        const photo = placeDetails.photos[i];
        const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsApiKey}`;
        photos.push(photoUrl);
      }
    }
    
    // Determine category from types
    let category = 'other';
    if (placeDetails.types) {
      if (placeDetails.types.includes('restaurant') || placeDetails.types.includes('food')) {
        category = 'restaurant';
      } else if (placeDetails.types.includes('cafe')) {
        category = 'cafe';
      } else if (placeDetails.types.includes('bar') || placeDetails.types.includes('night_club')) {
        category = 'bar';
      } else if (placeDetails.types.includes('shopping_mall') || placeDetails.types.includes('store')) {
        category = 'shopping';
      } else if (placeDetails.types.includes('museum') || placeDetails.types.includes('art_gallery')) {
        category = 'entertainment';
      }
    }
    
    return {
      googlePlaceId: placeId,
      name: placeDetails.name || placeName,
      address: placeDetails.formatted_address || '',
      photos: photos,
      category: category,
      rating: placeDetails.rating || null,
      priceLevel: placeDetails.price_level || null,
      website: placeDetails.website || null,
      phoneNumber: placeDetails.formatted_phone_number || null,
      // Convert Google's weekday_text strings to { day, hours } objects -
      // the iOS OpeningHour model requires an integer `day` and fails to
      // decode plain strings (which breaks any response containing the place)
      openingHours: placeDetails.opening_hours && placeDetails.opening_hours.weekday_text
        ? placeDetails.opening_hours.weekday_text.map((text, i) => {
            const dayIndex = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
            const dayName = text.split(':')[0].trim().toLowerCase();
            // weekday_text is Monday-first; iOS uses 0=Sunday, so the positional
            // fallback (unrecognized day name) is (i + 1) % 7
            return { day: dayIndex[dayName] != null ? dayIndex[dayName] : (i + 1) % 7, hours: text };
          })
        : null
    };
  } catch (error) {
    console.error('Error enriching place with Google data:', error);
    return {};
  }
}

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
        // Save notification to Firestore
        const notificationData = createNotification({
          userId: notifiedUserId,
          type: 'check_in',
          title: 'Check-in Notification',
          body: `${userData.displayName} is at ${checkIn.placeName}${checkIn.message ? ': ' + checkIn.message : ''}`,
          data: {
            checkInId: checkInId,
            placeName: checkIn.placeName,
            fromUserId: userId,
            fromUserName: userData.displayName,
            fromUserPhoto: userData.profilePicture || null,
            message: checkIn.message || null
          }
        });

        const validationErrors = validateNotification(notificationData);
        if (validationErrors.length === 0) {
          const notificationRef = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
          
          // Send SSE event for real-time notification count update
          sseService.notifyUser(notifiedUserId, 'new_notification', {
            notificationId: notificationRef.id,
            type: 'check_in',
            title: notificationData.title,
            body: notificationData.body,
            data: notificationData.data
          });
        } else {
          console.error('❌ Validation errors for check-in notification:', validationErrors);
        }

        // Also send push notification
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
      let circleIdForActivity = checkIn.circleId;
      
      if (checkIn.placeId) {
        // Check if place exists in database
        try {
          const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(checkIn.placeId).get();
          if (placeDoc.exists) {
            const placeData = placeDoc.data();
            if (placeData.photos && placeData.photos.length > 0) {
              placePhoto = placeData.photos[0];
            }
            circleIdForActivity = placeData.circleId || circleIdForActivity;
          } else {
            // Place ID provided but doesn't exist - clear it to create new
            finalPlaceId = null;
          }
        } catch (error) {
          console.error('Error fetching existing place for activity:', error);
          finalPlaceId = null;
        }
      }
      
      // If no valid place ID, create a new place in the check-in circle
      if (!finalPlaceId) {
        try {
          // Get or create the user's check-in circle
          const checkInCircle = await findOrCreateCheckInCircle(userId);
          circleIdForActivity = checkInCircle.id;
          
          // First check if a place with same name already exists in any of user's circles
          const existingPlacesQuery = await db.collection(COLLECTIONS.PLACES)
            .where('name', '==', checkIn.placeName)
            .where('addedBy', '==', userId)
            .where('deletedAt', '==', null)
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
            // Enrich place data with Google Places API
            const googleData = await enrichPlaceWithGoogleData(
              checkIn.placeName,
              checkIn.location
            );
            
            // Create new place in check-in circle with enriched data
            const placeData = {
              name: googleData.name || checkIn.placeName,
              address: googleData.address || checkIn.placeAddress,
              location: checkIn.location ? {
                coordinates: [checkIn.location.longitude, checkIn.location.latitude]
              } : null,
              category: googleData.category || checkIn.placeCategory || 'other',
              photos: googleData.photos || [],
              googlePlaceId: googleData.googlePlaceId || null,
              rating: googleData.rating || null,
              priceLevel: googleData.priceLevel || null,
              website: googleData.website || null,
              phoneNumber: googleData.phoneNumber || null,
              openingHours: googleData.openingHours || null,
              addedViaCheckIn: true
            };
            
            // Create the place document in the check-in circle
            const place = createPlace(placeData, checkInCircle.id, userId);
            const placeRef = await db.collection(COLLECTIONS.PLACES).add(place);
            finalPlaceId = placeRef.id;

            // Link the save to its canonical venue record (best-effort)
            const { ensureGlobalPlaceLink } = require('../services/globalPlaceResolver');
            await ensureGlobalPlaceLink(await placeRef.get());
            
            // Update the circle's places array
            await db.collection(COLLECTIONS.CIRCLES).doc(checkInCircle.id).update({
              places: FieldValue.arrayUnion(finalPlaceId)
            });
            
            // Use the first photo for activity thumbnail
            if (placeData.photos && placeData.photos.length > 0) {
              placePhoto = placeData.photos[0];
            }
            
            console.log(`✅ Created enriched place in check-in circle: ${placeData.name} (ID: ${finalPlaceId})`);
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
          circleId: circleIdForActivity,
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