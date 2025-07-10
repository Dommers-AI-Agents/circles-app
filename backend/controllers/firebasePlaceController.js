// backend/controllers/firebasePlaceController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createPlace, 
  validatePlace,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');
const notificationService = require('../services/notificationService');
const { trackPlaceAdded, trackPlaceView } = require('../services/activityService');

const db = getFirestore();
const googleMapsClient = new Client({});

// @desc    Get places by circle ID
// @route   GET /api/circles/:circleId/places
// @access  Private
exports.getPlacesByCircleId = async (req, res, next) => {
  try {
    const { circleId } = req.params;

    // First verify user has access to this circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    console.log('🔍 getPlacesByCircleId - Circle access check:', {
      circleId: circleId,
      circleName: circle.name,
      circleOwner: circle.owner,
      circlePrivacy: circle.privacy,
      requestingUser: req.user.uid,
      sharedWith: circle.sharedWith || []
    });
    
    // Check permissions
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    const isPublic = circle.privacy === 'public';
    
    // For myNetwork privacy, check if users are connected
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      // Check if the current user is connected to the circle owner
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', req.user.uid)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', req.user.uid)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
      
      console.log('🔍 Connection check results:', {
        connection1Count: connection1.size,
        connection2Count: connection2.size,
        isConnected: isConnected
      });
    }
    
    console.log('🔍 Permission check results:', {
      isOwner,
      isSharedWith,
      isPublic,
      isConnected,
      circlePrivacy: circle.privacy,
      willAllowAccess: isOwner || isSharedWith || isPublic || (circle.privacy === 'myNetwork' && isConnected)
    });
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }

    // Get places for this circle, ordered by creation date (newest first)
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();

    const places = serializeQuerySnapshot(placesSnapshot);
    
    // Get unique user IDs who added places
    const userIds = [...new Set(places.map(place => place.addedBy))];
    
    // Fetch user information for all users who added places
    const userPromises = userIds.map(userId => {
      // Handle complex ID format if needed
      let actualUserId = userId;
      if (userId && userId.includes('.')) {
        const parts = userId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1]; // Use the middle part as Firebase UID
        }
      }
      return db.collection(COLLECTIONS.USERS).doc(actualUserId).get();
    });
    const userDocs = await Promise.all(userPromises);
    
    // Create a map of user information
    const userMap = new Map();
    userDocs.forEach((doc, index) => {
      if (doc.exists) {
        const userData = serializeDoc(doc);
        const originalUserId = userIds[index]; // The original ID from the place
        
        // Map both the simple and complex ID formats
        userMap.set(userData.id, {
          id: userData.id,
          displayName: userData.displayName || 'Unknown User',
          email: userData.email,
          profilePicture: userData.profilePicture
        });
        
        // Also map the original ID if it's different
        if (originalUserId !== userData.id) {
          userMap.set(originalUserId, {
            id: userData.id,
            displayName: userData.displayName || 'Unknown User',
            email: userData.email,
            profilePicture: userData.profilePicture
          });
        }
      }
    });
    
    // Add user information to each place
    const placesWithUsers = places.map(place => ({
      ...place,
      addedByUser: userMap.get(place.addedBy) || null
    }));
    
    // Create a map for quick lookup
    const placesMap = new Map();
    placesWithUsers.forEach(place => {
      placesMap.set(place.id, place);
    });
    
    // Return places in the order specified in the circle's places array
    let orderedPlaces = [];
    if (circle.places && circle.places.length > 0) {
      orderedPlaces = circle.places
        .map(placeId => placesMap.get(placeId))
        .filter(place => place !== undefined); // Filter out any deleted places
    } else {
      // Fallback to date-based sorting if no order is specified
      orderedPlaces = placesWithUsers.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    
    console.log('Circle places order:', circle.places || []);
    console.log('Returning places in order:', orderedPlaces.map(p => ({ 
      id: p.id, 
      name: p.name,
      addedBy: p.addedBy,
      addedByUser: p.addedByUser ? p.addedByUser.displayName : 'No user info'
    })));

    res.status(200).json({
      success: true,
      count: orderedPlaces.length,
      places: orderedPlaces
    });
  } catch (error) {
    console.error('Error fetching places:', error);
    next(error);
  }
};

// @desc    Get single place
// @route   GET /api/places/:id
// @access  Private
exports.getPlace = async (req, res, next) => {
  try {
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(req.params.id).get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Check if user has access to the circle this place belongs to
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Check permissions
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith.includes(req.user.uid);
    const isPublic = circle.privacy === 'public';
    
    if (!isOwner && !isSharedWith && !isPublic) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this place'
      });
    }

    res.status(200).json({
      success: true,
      place: place
    });
  } catch (error) {
    console.error('Error fetching place:', error);
    next(error);
  }
};

// @desc    Create new place
// @route   POST /api/places
// @access  Private
exports.createPlace = async (req, res, next) => {
  try {
    const { circleId } = req.body;

    if (!circleId) {
      return res.status(400).json({
        success: false,
        message: 'Circle ID is required'
      });
    }

    // Verify circle exists and user has permission
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Check if user can add places (owner or shared with)
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith.includes(req.user.uid);
    
    if (!isOwner && !isSharedWith) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to add places to this circle'
      });
    }

    // Validate place data
    const validationErrors = validatePlace(req.body);
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Check for duplicates before creating
    const { googlePlaceId, name, address } = req.body;
    
    if (googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', googlePlaceId)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the selected circle'
        });
      }
    } else if (name && address) {
      // For custom places without googlePlaceId
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('name', '==', name)
        .where('address', '==', address)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the selected circle'
        });
      }
    }

    // Create place data
    const placeData = createPlace(req.body, circleId, req.user.uid);
    
    // Add to Firestore
    const placeRef = await db.collection(COLLECTIONS.PLACES).add(placeData);
    
    // Get the created place with ID
    const createdPlace = await placeRef.get();
    const place = serializeDoc(createdPlace);

    // Update circle's places array and increment count (only add if place.id is defined)
    const currentPlaces = circle.places || [];
    if (place.id) {
      await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
        places: [place.id, ...currentPlaces], // Add new place at the beginning
        placesCount: (circle.placesCount || 0) + 1, // Increment places count
        updatedAt: new Date().toISOString()
      });
    }

    res.status(201).json({
      success: true,
      place: place
    });

    // Track activity for network connections
    await trackPlaceAdded(placeRef.id, circleId, place.name, circle.name, req.user.uid);

    // Send notifications to interested users
    try {
      // Get users who should be notified
      const notifyUserIds = new Set();
      
      // Add circle members (if not private)
      if (circle.privacy !== 'private') {
        // Add shared users
        circle.sharedWith.forEach(userId => {
          if (userId !== req.user.uid) {
            notifyUserIds.add(userId);
          }
        });
        
        // Add circle owner if not the one adding
        if (circle.owner !== req.user.uid) {
          notifyUserIds.add(circle.owner);
        }
        
        // If circle is public, add user's network
        if (circle.privacy === 'public' || circle.privacy === 'myNetwork') {
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            const connections = userData.friends || [];
            connections.forEach(userId => notifyUserIds.add(userId));
          }
        }
      }
      
      if (notifyUserIds.size > 0) {
        await notificationService.notifyNewPlace(
          place,
          circle,
          Array.from(notifyUserIds)
        );
      }
    } catch (notifError) {
      console.error('Error sending place notifications:', notifError);
      // Don't fail the request if notifications fail
    }
  } catch (error) {
    console.error('Error creating place:', error);
    next(error);
  }
};

// @desc    Update place
// @route   PUT /api/places/:id
// @access  Private
exports.updatePlace = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Check if user can edit (owner of circle or person who added the place)
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
    const circle = serializeDoc(circleDoc);
    
    const isCircleOwner = circle.owner === req.user.uid;
    const isPlaceAdder = place.addedBy === req.user.uid;
    
    if (!isCircleOwner && !isPlaceAdder) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this place'
      });
    }

    // Validate updates
    const validationErrors = validatePlace({ ...place, ...req.body });
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Don't allow changing circleId or addedBy
    const { circleId, addedBy, ...updateData } = req.body;
    updateData.updatedAt = new Date().toISOString();

    await placeRef.update(updateData);
    
    // Get updated place
    const updatedPlaceDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedPlaceDoc);

    res.status(200).json({
      success: true,
      place: updatedPlace
    });
  } catch (error) {
    console.error('Error updating place:', error);
    next(error);
  }
};

// @desc    Delete place
// @route   DELETE /api/places/:id
// @access  Private
exports.deletePlace = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Check if user can delete (owner of circle or person who added the place)
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
    const circle = serializeDoc(circleDoc);
    
    const isCircleOwner = circle.owner === req.user.uid;
    const isPlaceAdder = place.addedBy === req.user.uid;
    
    if (!isCircleOwner && !isPlaceAdder) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this place'
      });
    }

    // Use a batch write for atomic operation
    const batch = db.batch();
    
    // Remove place from circle's places array and decrement count
    const currentPlaces = circle.places || [];
    const updatedPlaces = currentPlaces.filter(placeId => placeId !== req.params.id);
    
    // Store the original circle state for potential rollback
    const originalCircleState = {
      places: currentPlaces,
      placesCount: circle.placesCount || 0
    };
    
    try {
      // Update circle in the batch
      const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
      batch.update(circleRef, {
        places: updatedPlaces,
        placesCount: Math.max(0, (circle.placesCount || 0) - 1), // Decrement places count (never go below 0)
        updatedAt: new Date().toISOString()
      });
      
      // Delete the place in the batch
      batch.delete(placeRef);
      
      // Commit the batch
      await batch.commit();
      
      console.log('✅ Place deleted successfully:', req.params.id);
      
      // Add a small delay to allow Firestore to propagate the deletion
      // This helps prevent "place already exists" errors when immediately re-adding
      await new Promise(resolve => setTimeout(resolve, 500));

      res.status(200).json({
        success: true,
        message: 'Place deleted successfully'
      });
    } catch (batchError) {
      // If batch operation fails, attempt to restore the original state
      console.error('❌ Batch delete failed, attempting rollback:', batchError);
      
      try {
        await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).update({
          places: originalCircleState.places,
          placesCount: originalCircleState.placesCount,
          updatedAt: new Date().toISOString()
        });
        console.log('✅ Rollback successful');
      } catch (rollbackError) {
        console.error('❌ Rollback failed:', rollbackError);
      }
      
      throw batchError;
    }
  } catch (error) {
    console.error('Error deleting place:', error);
    next(error);
  }
};

// @desc    Search places
// @route   GET /api/places/search
// @access  Private
exports.searchPlaces = async (req, res, next) => {
  try {
    const { q: query, category } = req.query;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    let placesRef = db.collection(COLLECTIONS.PLACES);

    // Filter by category if provided
    if (category) {
      placesRef = placesRef.where('category', '==', category);
    }

    // Note: Firestore doesn't have full-text search built-in
    // For production, you'd want to use Algolia or similar
    // For now, we'll do a simple name search
    const snapshot = await placesRef
      .where('name', '>=', query)
      .where('name', '<=', query + '\uf8ff')
      .limit(50)
      .get();

    const places = serializeQuerySnapshot(snapshot);

    // Filter results to only include places from circles the user can access
    const accessiblePlaces = [];
    for (const place of places) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
      if (circleDoc.exists) {
        const circle = serializeDoc(circleDoc);
        const isOwner = circle.owner === req.user.uid;
        const isSharedWith = circle.sharedWith.includes(req.user.uid);
        const isPublic = circle.privacy === 'public';
        
        if (isOwner || isSharedWith || isPublic) {
          accessiblePlaces.push(place);
        }
      }
    }

    // Sort results by name
    accessiblePlaces.sort((a, b) => a.name.localeCompare(b.name));

    res.status(200).json({
      success: true,
      count: accessiblePlaces.length,
      places: accessiblePlaces
    });
  } catch (error) {
    console.error('Error searching places:', error);
    next(error);
  }
};

// @desc    Refresh place data from Google Places API
// @route   POST /api/places/:id/refresh-google
// @access  Private (owner or circle member)
exports.refreshPlaceFromGoogle = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check permissions
    const isOwner = place.addedBy === req.user.uid;
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Associated circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    const isCircleMember = circle.owner === req.user.uid || 
                          (circle.sharedWith && circle.sharedWith.includes(req.user.uid));
    
    if (!isOwner && !isCircleMember) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to refresh this place'
      });
    }
    
    // Check if place has Google Place ID
    if (!place.googlePlaceId) {
      return res.status(400).json({
        success: false,
        message: 'This place does not have a Google Place ID'
      });
    }
    
    try {
      // Fetch fresh data from Google Places API
      console.log('Fetching Google Place details for:', place.googlePlaceId);
      console.log('Using API key:', googleMapsApiKey ? 'Key exists' : 'No API key!');
      
      const response = await googleMapsClient.placeDetails({
        params: {
          place_id: place.googlePlaceId,
          fields: [
            'name',
            'formatted_address',
            'formatted_phone_number',
            'website',
            'rating',
            'user_ratings_total',
            'price_level',
            'types',
            'opening_hours',
            'photos',
            'reviews',
            'business_status'
          ].join(','),
          key: googleMapsApiKey
        }
      });
      
      const googleData = response.data.result;
      
      // Prepare update data
      const updateData = {
        updatedAt: new Date()
      };
      
      // Update fields with fresh Google data
      if (googleData.name) updateData.name = googleData.name;
      if (googleData.formatted_address) updateData.address = googleData.formatted_address;
      if (googleData.formatted_phone_number) updateData.phone = googleData.formatted_phone_number;
      if (googleData.website) updateData.website = googleData.website;
      if (googleData.rating) updateData.rating = googleData.rating;
      if (googleData.user_ratings_total) updateData.userRatingsTotal = googleData.user_ratings_total;
      
      // Update price level
      if (googleData.price_level !== undefined) {
        updateData.priceLevel = googleData.price_level;
      }
      
      // Update opening hours
      if (googleData.opening_hours && googleData.opening_hours.periods) {
        updateData.openingHours = googleData.opening_hours.periods.map(period => ({
          day: period.open.day,
          open: `${String(period.open.hours).padStart(2, '0')}:${String(period.open.minutes).padStart(2, '0')}`,
          close: period.close ? `${String(period.close.hours).padStart(2, '0')}:${String(period.close.minutes).padStart(2, '0')}` : '23:59',
          isClosed: false
        }));
      }
      
      // Update reviews from Google
      if (googleData.reviews && googleData.reviews.length > 0) {
        updateData.reviews = googleData.reviews.map(review => ({
          user: review.author_name,
          rating: review.rating,
          comment: review.text,
          date: new Date(review.time * 1000) // Convert Unix timestamp to Date
        }));
      }
      
      // Update the place in Firestore
      await placeRef.update(updateData);
      
      // Get the updated place
      const updatedDoc = await placeRef.get();
      const updatedPlace = serializeDoc(updatedDoc);
      
      res.status(200).json({
        success: true,
        place: updatedPlace
      });
      
    } catch (googleError) {
      console.error('Google Places API Error:', googleError);
      console.error('Error response data:', googleError.response?.data);
      console.error('Error status:', googleError.response?.status);
      
      // Check for specific error types
      if (googleError.response?.status === 403) {
        return res.status(500).json({
          success: false,
          message: 'Google Places API access denied. Please check API key and ensure Places API is enabled.'
        });
      }
      
      return res.status(500).json({
        success: false,
        message: `Failed to fetch data from Google Places: ${googleError.message}`
      });
    }
    
  } catch (error) {
    console.error('Error refreshing place from Google:', error);
    next(error);
  }
};

// @desc    Reorder places within a circle
// @route   PUT /api/circles/:id/places/reorder
// @access  Private
exports.reorderPlacesInCircle = async (req, res, next) => {
  try {
    const { placeIds } = req.body;
    const circleId = req.params.id;
    
    if (!placeIds || !Array.isArray(placeIds)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide an array of place IDs'
      });
    }
    
    // Get the circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Make sure user owns the circle
    if (circle.owner !== req.user.uid) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to modify this circle'
      });
    }
    
    // Verify all place IDs exist in the circle
    const existingPlaceIds = circle.places || [];
    const providedPlaceIds = placeIds;
    
    // Check if all provided IDs exist in the circle
    const allIdsExist = providedPlaceIds.every(id => existingPlaceIds.includes(id));
    
    if (!allIdsExist) {
      return res.status(400).json({
        success: false,
        message: 'Invalid place IDs - some places do not belong to this circle'
      });
    }
    
    // Check if all circle places are accounted for
    if (providedPlaceIds.length !== existingPlaceIds.length) {
      return res.status(400).json({
        success: false,
        message: 'All places in the circle must be included in the reorder'
      });
    }
    
    // Update the places array with the new order
    console.log('Reordering places from:', existingPlaceIds);
    console.log('Reordering places to:', placeIds);
    
    await circleRef.update({
      places: placeIds,
      updatedAt: new Date().toISOString()
    });
    
    console.log('Saved circle with new order:', placeIds);
    
    res.status(200).json({
      success: true,
      message: 'Places reordered successfully'
    });
    
  } catch (error) {
    console.error('Error reordering places:', error);
    next(error);
  }
};

// @desc    Like a place
// @route   POST /api/places/:id/like
// @access  Private
exports.likePlace = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    
    // Get the place
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user has permission to view this place
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    // Check if users are connected for myNetwork privacy
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to like this place'
      });
    }
    
    // Check if already liked
    const likes = place.likes || [];
    const alreadyLiked = likes.includes(userId);
    
    let updatedLikes;
    let updatedLikesCount;
    
    if (alreadyLiked) {
      // Unlike
      updatedLikes = likes.filter(id => id !== userId);
      updatedLikesCount = Math.max(0, (place.likesCount || 0) - 1);
    } else {
      // Like
      updatedLikes = [...likes, userId];
      updatedLikesCount = (place.likesCount || 0) + 1;
    }
    
    // Update the place
    await placeRef.update({
      likes: updatedLikes,
      likesCount: updatedLikesCount,
      updatedAt: new Date().toISOString()
    });
    
    // Get updated place
    const updatedDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedDoc);
    
    // Send notification to place owner if someone liked their place (not unliked, and not their own place)
    if (!alreadyLiked && place.addedBy !== userId) {
      await notificationService.sendPlaceLikeNotification(
        place.addedBy,
        userId,
        placeId,
        place.name
      );
    }
    
    res.status(200).json({
      success: true,
      liked: !alreadyLiked,
      place: updatedPlace
    });
    
  } catch (error) {
    console.error('Error liking place:', error);
    next(error);
  }
};

// @desc    Get comments for a place
// @route   GET /api/places/:id/comments
// @access  Private
exports.getPlaceComments = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    
    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check permissions (same as likePlace)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view comments for this place'
      });
    }
    
    // Get comments
    const commentsSnapshot = await db.collection('placeComments')
      .where('placeId', '==', placeId)
      .orderBy('createdAt', 'desc')
      .get();
    
    const comments = [];
    for (const doc of commentsSnapshot.docs) {
      const comment = serializeDoc(doc);
      
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
      if (userDoc.exists) {
        comment.user = serializeDoc(userDoc);
      }
      
      comments.push(comment);
    }
    
    res.status(200).json({
      success: true,
      comments: comments
    });
    
  } catch (error) {
    console.error('Error getting place comments:', error);
    next(error);
  }
};

// @desc    Add comment to a place
// @route   POST /api/places/:id/comments
// @access  Private
exports.addPlaceComment = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    const { text } = req.body;
    
    if (!text || text.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Comment text is required'
      });
    }
    
    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check permissions (same as likePlace)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to comment on this place'
      });
    }
    
    // Create comment
    const commentData = {
      placeId: placeId,
      userId: userId,
      text: text.trim(),
      createdAt: new Date().toISOString()
    };
    
    const commentRef = await db.collection('placeComments').add(commentData);
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      comment.user = serializeDoc(userDoc);
    }
    
    // Send notification to place owner if it's not the commenter
    if (place.addedBy !== userId) {
      await notificationService.sendPlaceCommentNotification(
        place.addedBy,
        userId,
        placeId,
        place.name,
        text.trim()
      );
    }
    
    res.status(201).json({
      success: true,
      comment: comment
    });
    
  } catch (error) {
    console.error('Error adding place comment:', error);
    next(error);
  }
};

// @desc    Add existing place to a circle
// @route   POST /api/places/:id/add-to-circle/:circleId
// @access  Private
exports.addExistingPlaceToCircle = async (req, res, next) => {
  try {
    const { id: placeId, circleId } = req.params; // Route uses :id, not :placeId
    const userId = req.user.uid;
    const { notes } = req.body;
    
    console.log('🔄 Adding existing place to circle:', {
      placeId,
      circleId,
      userId,
      notes
    });
    
    // Validate input parameters
    if (!placeId || placeId.trim() === '') {
      console.error('❌ Invalid placeId:', placeId);
      return res.status(400).json({
        success: false,
        message: 'Invalid place ID provided'
      });
    }
    
    if (!circleId || circleId.trim() === '') {
      console.error('❌ Invalid circleId:', circleId);
      return res.status(400).json({
        success: false,
        message: 'Invalid circle ID provided'
      });
    }
    
    // Check if the place exists
    let placeRef, placeDoc;
    try {
      console.log('📄 Attempting to get place document with ID:', placeId);
      placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
      placeDoc = await placeRef.get();
    } catch (docError) {
      console.error('❌ Error accessing place document:', docError);
      console.error('❌ PlaceId that caused error:', placeId);
      return res.status(500).json({
        success: false,
        message: 'Failed to access place document',
        error: docError.message
      });
    }
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const originalPlace = serializeDoc(placeDoc);
    
    // Check if the circle exists and user has access
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Verify user owns the target circle
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You can only add places to your own circles'
      });
    }
    
    // Check if place already exists in this circle
    console.log('🔍 Checking for duplicate place:', {
      circleId,
      placeId,
      googlePlaceId: originalPlace.googlePlaceId,
      name: originalPlace.name,
      address: originalPlace.address
    });
    
    if (originalPlace.googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', originalPlace.googlePlaceId)
        .get();
        
      console.log('🔍 Google Place ID duplicate check:', {
        googlePlaceId: originalPlace.googlePlaceId,
        foundDuplicates: !existingPlace.empty,
        duplicateCount: existingPlace.size
      });
        
      if (!existingPlace.empty) {
        // Double-check if the document actually exists (not just in query cache)
        const firstDoc = existingPlace.docs[0];
        const docStillExists = await db.collection(COLLECTIONS.PLACES).doc(firstDoc.id).get();
        
        if (docStillExists.exists) {
          console.log('⚠️ Duplicate place found:', {
            duplicateId: firstDoc.id,
            duplicateData: firstDoc.data()
          });
          
          return res.status(400).json({
            success: false,
            message: 'This place already exists in the selected circle'
          });
        } else {
          console.log('✅ False positive - document was deleted but still in query cache');
        }
      }
    } else {
      // For places without googlePlaceId, check by name and address
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('name', '==', originalPlace.name)
        .where('address', '==', originalPlace.address)
        .get();
        
      console.log('🔍 Name/Address duplicate check:', {
        name: originalPlace.name,
        address: originalPlace.address,
        foundDuplicates: !existingPlace.empty,
        duplicateCount: existingPlace.size
      });
        
      if (!existingPlace.empty) {
        // Double-check if the document actually exists (not just in query cache)
        const firstDoc = existingPlace.docs[0];
        const docStillExists = await db.collection(COLLECTIONS.PLACES).doc(firstDoc.id).get();
        
        if (docStillExists.exists) {
          console.log('⚠️ Duplicate place found:', {
            duplicateId: firstDoc.id,
            duplicateData: firstDoc.data()
          });
          
          return res.status(400).json({
            success: false,
            message: 'This place already exists in the selected circle'
          });
        } else {
          console.log('✅ False positive - document was deleted but still in query cache');
        }
      }
    }
    
    // Create a new place entry for this circle
    // Copy all fields except ID fields
    const { _id, id, ...placeDataWithoutIds } = originalPlace;
    
    const newPlaceData = {
      ...placeDataWithoutIds,
      circleId: circleId,
      addedBy: userId,
      notes: notes || originalPlace.notes || null,
      publicNotes: notes || originalPlace.publicNotes || null,
      privateNotes: null, // Reset private notes for the new copy
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      likes: [], // Reset likes for the new copy
      likesCount: 0
    };
    
    // Create the new place
    const newPlaceRef = await db.collection(COLLECTIONS.PLACES).add(newPlaceData);
    const newPlaceId = newPlaceRef.id; // Get the ID directly from the reference
    
    console.log('🆕 New place created with ID:', newPlaceId);
    
    // Verify the place was created successfully
    if (!newPlaceId) {
      throw new Error('Failed to create new place - no document ID generated');
    }
    
    // Get the created place document
    const newPlaceDoc = await newPlaceRef.get();
    const newPlace = serializeDoc(newPlaceDoc);
    
    // Update circle's places array and increment count using the direct ID
    const currentPlaces = circle.places || [];
    await circleRef.update({
      places: [...currentPlaces, newPlaceId], // Use the ID we got from the reference
      placesCount: (circle.placesCount || 0) + 1, // Increment places count
      updatedAt: new Date().toISOString()
    });
    
    // Track activity
    if (trackPlaceAdded) {
      await trackPlaceAdded(newPlaceId, circleId, newPlace.name, circle.name, userId);
    }
    
    res.status(201).json({
      success: true,
      message: 'Place added to circle successfully',
      place: newPlace
    });
    
  } catch (error) {
    console.error('Error adding existing place to circle:', error);
    console.error('Error details:', {
      message: error.message,
      stack: error.stack,
      placeId: req.params.placeId,
      circleId: req.params.circleId,
      userId: req.user?.uid
    });
    
    // Send a more detailed error response
    return res.status(500).json({
      success: false,
      message: 'Failed to add place to circle',
      error: error.message
    });
  }
};

// @desc    Track when a user views a place
// @route   POST /api/places/:id/track-view
// @access  Private
exports.trackPlaceView = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const viewerUserId = req.user.firebaseDocId || req.user.uid;
    const { connectionUserId } = req.body;
    
    if (!connectionUserId) {
      return res.status(400).json({
        success: false,
        message: 'Connection user ID is required'
      });
    }
    
    // Track the view in activity service
    await trackPlaceView(viewerUserId, placeId, connectionUserId);
    
    res.status(200).json({
      success: true,
      message: 'Place view tracked'
    });
  } catch (error) {
    console.error('Error tracking place view:', error);
    next(error);
  }
};