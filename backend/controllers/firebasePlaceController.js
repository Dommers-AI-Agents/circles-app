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
    console.log('🔍 getPlacesByCircleId - START - Request details:', {
      circleId: req.params.circleId,
      userUid: req.user?.uid,
      userEmail: req.user?.email,
      method: req.method,
      url: req.url
    });

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
      sharedWith: circle.sharedWith || [],
      placesArray: circle.places || []
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
    // Filter out soft-deleted places - need to handle both null and undefined values
    console.log('🔍 About to query places with:', {
      collection: COLLECTIONS.PLACES,
      circleId: circleId,
      note: 'Getting all places, will filter deletedAt != null in code since Firestore treats null and undefined differently'
    });
    
    // First get all places for this circle, then filter in code since Firestore 
    // treats null and undefined differently and we need to exclude only non-null values
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();
      
    console.log('🔍 Places query results:', {
      isEmpty: placesSnapshot.empty,
      size: placesSnapshot.size,
      docs: placesSnapshot.docs.map(doc => ({
        id: doc.id,
        data: doc.data()
      }))
    });
    
    // DEBUG: Let's check what the deletedAt field actually contains for these places
    if (circle.places && circle.places.length > 0) {
      console.log('🔍 DEBUG: Checking first 3 places in circle for deletedAt values...');
      for (let i = 0; i < Math.min(3, circle.places.length); i++) {
        const placeId = circle.places[i];
        try {
          const debugPlaceDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
          if (debugPlaceDoc.exists) {
            const placeData = debugPlaceDoc.data();
            console.log(`🔍 Place ${placeId}:`, {
              id: placeId,
              deletedAt: placeData.deletedAt,
              deletedAtType: typeof placeData.deletedAt,
              circleId: placeData.circleId,
              hasDeletedAtField: placeData.hasOwnProperty('deletedAt')
            });
          } else {
            console.log(`🔍 Place ${placeId}: Document does not exist`);
          }
        } catch (error) {
          console.log(`🔍 Place ${placeId}: Error fetching:`, error.message);
        }
      }
    }

    // Filter out soft-deleted places (where deletedAt is not null/undefined)
    const allPlaces = serializeQuerySnapshot(placesSnapshot);
    const places = allPlaces.filter(place => {
      const isDeleted = place.deletedAt !== null && place.deletedAt !== undefined;
      console.log(`🔍 Place ${place.id} (${place.name}): deletedAt=${place.deletedAt}, isDeleted=${isDeleted}`);
      return !isDeleted;
    });
    
    console.log('🔍 Filtering results:', {
      totalPlacesFromQuery: allPlaces.length,
      nonDeletedPlaces: places.length,
      filteredOutCount: allPlaces.length - places.length
    });
    
    // Debug location data for the first few places
    console.log('🗺️ Location data debug:');
    places.slice(0, 3).forEach((place, index) => {
      console.log(`🗺️ Place ${index + 1}: ${place.name}`);
      console.log(`  📍 Location field:`, place.location);
      if (place.location) {
        console.log(`  📍 Location type: ${typeof place.location}`);
        console.log(`  📍 Coordinates:`, place.location.coordinates);
        console.log(`  📍 Coordinates type: ${typeof place.location.coordinates}`);
        console.log(`  📍 Coordinates length: ${place.location.coordinates ? place.location.coordinates.length : 'N/A'}`);
        if (place.location.coordinates && place.location.coordinates.length === 2) {
          console.log(`  📍 Lng: ${place.location.coordinates[0]} (${typeof place.location.coordinates[0]})`);
          console.log(`  📍 Lat: ${place.location.coordinates[1]} (${typeof place.location.coordinates[1]})`);
        }
      } else {
        console.log(`  ❌ No location field`);
      }
    });
    
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
    
    // Fetch comment counts for all places
    const commentCountPromises = places.map(place => 
      db.collection('placeComments')
        .where('placeId', '==', place.id)
        .count()
        .get()
    );
    
    const commentCounts = await Promise.all(commentCountPromises);
    
    // Add user information and comment count to each place
    const placesWithUsers = places.map((place, index) => ({
      ...place,
      addedByUser: userMap.get(place.addedBy) || null,
      commentsCount: commentCounts[index].data().count || 0
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
    
    console.log('🔍 Circle places order:', circle.places || []);
    console.log('🔍 Total places found from query:', places.length);
    console.log('🔍 Returning places in order:', orderedPlaces.map(p => ({ 
      id: p.id, 
      name: p.name,
      addedBy: p.addedBy,
      addedByUser: p.addedByUser ? p.addedByUser.displayName : 'No user info',
      hasNotes: p.notes ? 'yes' : 'no',
      hasPublicNotes: p.publicNotes ? 'yes' : 'no',
      hasPrivateNotes: p.privateNotes ? 'yes' : 'no'
    })));

    console.log('🔍 getPlacesByCircleId - FINAL RESPONSE:', {
      success: true,
      count: orderedPlaces.length,
      placesReturnedToClient: orderedPlaces.length
    });

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

// @desc    Get places by circle ID (public access)
// @route   GET /api/circles/:circleId/places/public
// @access  Public
exports.getPlacesByCircleIdPublic = async (req, res, next) => {
  try {
    console.log('🔍 getPlacesByCircleIdPublic - START - Request details:', {
      circleId: req.params.circleId,
      method: req.method,
      url: req.url
    });

    const { circleId } = req.params;

    // First get the circle to check if it's public
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    console.log('🔍 getPlacesByCircleIdPublic - Circle check:', {
      circleId: circleId,
      circleName: circle.name,
      circlePrivacy: circle.privacy
    });
    
    // Only allow access to public circles
    if (circle.privacy !== 'public') {
      return res.status(403).json({
        success: false,
        message: 'This circle is not public'
      });
    }
    
    // Get all places for this circle using the same query method as authenticated endpoint
    console.log('🔍 getPlacesByCircleIdPublic - Querying places by circleId:', circleId);
    
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();
    
    console.log('🔍 Public places query results:', {
      isEmpty: placesSnapshot.empty,
      size: placesSnapshot.size
    });
    
    // Filter out soft-deleted places
    const allPlaces = serializeQuerySnapshot(placesSnapshot);
    const places = allPlaces.filter(place => {
      const isDeleted = place.deletedAt !== null && place.deletedAt !== undefined;
      return !isDeleted;
    });
    
    console.log(`🔍 Found ${places.length} active places for public circle`);
    
    // Get unique user IDs who added places
    const userIds = [...new Set(places.map(place => place.addedBy))];
    
    // Fetch user information for all users who added places
    const userPromises = userIds.map(userId => {
      let actualUserId = userId;
      if (userId && userId.includes('.')) {
        const parts = userId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1];
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
        const originalUserId = userIds[index];
        
        userMap.set(userData.id, {
          id: userData.id,
          displayName: userData.displayName || 'Unknown User',
          email: userData.email,
          profilePicture: userData.profilePicture
        });
        
        if (originalUserId !== userData.id) {
          userMap.set(originalUserId, userMap.get(userData.id));
        }
      }
    });
    
    // Attach user information to each place
    const placesWithUsers = places.map(place => ({
      ...place,
      addedByUser: userMap.get(place.addedBy) || null
    }));
    
    // Order places - if circle has places array, use it for ordering, otherwise use creation date
    let orderedPlaces = [];
    if (circle.places && circle.places.length > 0) {
      // Create a map for quick lookup
      const placesMap = new Map();
      placesWithUsers.forEach(place => {
        placesMap.set(place.id, place);
      });
      
      // Return places in the order specified in the circle's places array
      orderedPlaces = circle.places
        .map(placeId => placesMap.get(placeId))
        .filter(place => place !== undefined); // Filter out any deleted places
    } else {
      // Fallback to date-based sorting if no order is specified
      orderedPlaces = placesWithUsers.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    
    console.log(`🔍 Returning ${orderedPlaces.length} ordered places for public circle`);
    
    res.status(200).json({
      success: true,
      count: orderedPlaces.length,
      places: orderedPlaces
    });
  } catch (error) {
    console.error('Error fetching public places:', error);
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
    
    // Check if place is soft-deleted
    if (place.deletedAt) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

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

    // Get comment count for this place
    const commentCountSnapshot = await db.collection('placeComments')
      .where('placeId', '==', req.params.id)
      .count()
      .get();
    
    const commentsCount = commentCountSnapshot.data().count || 0;
    
    res.status(200).json({
      success: true,
      place: {
        ...place,
        commentsCount
      }
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

    // Check for duplicates before creating (excluding soft-deleted places)
    const { googlePlaceId, name, address } = req.body;
    
    if (googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', googlePlaceId)
        .where('deletedAt', '==', null)
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
        .where('deletedAt', '==', null)
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
    
    // If location is missing but address is provided, try to geocode it
    if (!placeData.location && placeData.address && googleMapsApiKey) {
      console.log('🗺️ Place missing location, attempting to geocode address:', placeData.address);
      try {
        const geocodeResponse = await googleMapsClient.geocode({
          params: {
            address: placeData.address,
            key: googleMapsApiKey
          }
        });
        
        if (geocodeResponse.data.results && geocodeResponse.data.results.length > 0) {
          const result = geocodeResponse.data.results[0];
          const { lat, lng } = result.geometry.location;
          
          // Validate coordinates
          if (typeof lng === 'number' && typeof lat === 'number' &&
              lng >= -180 && lng <= 180 &&
              lat >= -90 && lat <= 90 &&
              !(lng === -180 && lat === -180)) {
            placeData.location = {
              type: 'Point',
              coordinates: [lng, lat]
            };
            console.log('✅ Successfully geocoded address to:', { lat, lng });
          } else {
            console.warn('⚠️ Invalid coordinates from geocoding:', { lat, lng });
          }
        } else {
          console.warn('⚠️ No geocoding results for address:', placeData.address);
        }
      } catch (error) {
        console.warn('⚠️ Geocoding failed:', error.message);
        // Continue without location - not a fatal error
      }
    }
    
    // Log place creation for debugging
    console.log('🆕 Creating new place:', {
      name: placeData.name,
      circleId: circleId,
      addedBy: req.user.uid,
      hasLocation: !!placeData.location,
      notes: {
        notes: placeData.notes ? `${placeData.notes.substring(0, 50)}...` : 'empty',
        publicNotes: placeData.publicNotes ? `${placeData.publicNotes.substring(0, 50)}...` : 'empty',
        privateNotes: placeData.privateNotes ? `${placeData.privateNotes.substring(0, 50)}...` : 'empty'
      },
      category: placeData.category,
      googlePlaceId: placeData.googlePlaceId || 'none'
    });
    
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

    // Add commentsCount to the response (new places have 0 comments)
    res.status(201).json({
      success: true,
      place: {
        ...place,
        commentsCount: 0
      }
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
    
    // Validate location coordinates if provided
    if (updateData.location && updateData.location.coordinates) {
      const [longitude, latitude] = updateData.location.coordinates;
      
      // Validate coordinates are within valid ranges
      if (typeof longitude !== 'number' || typeof latitude !== 'number' ||
          longitude < -180 || longitude > 180 ||
          latitude < -90 || latitude > 90 ||
          // Reject coordinates at exactly -180, -180 (invalid/default values)
          (longitude === -180 && latitude === -180)) {
        console.warn('⚠️ Invalid coordinates rejected in update:', { longitude, latitude, placeId: req.params.id });
        delete updateData.location; // Remove invalid location from update
      }
    }
    
    // Log notes updates for debugging
    if (updateData.privateNotes !== undefined || updateData.publicNotes !== undefined || updateData.notes !== undefined) {
      console.log('📝 Updating place notes:', {
        placeId: req.params.id,
        userId: req.user.uid,
        placeAddedBy: place.addedBy,
        isPlaceAdder: isPlaceAdder,
        isCircleOwner: isCircleOwner,
        updates: {
          privateNotes: updateData.privateNotes !== undefined ? `${updateData.privateNotes?.substring(0, 50)}...` : 'not changed',
          publicNotes: updateData.publicNotes !== undefined ? `${updateData.publicNotes?.substring(0, 50)}...` : 'not changed',
          notes: updateData.notes !== undefined ? `${updateData.notes?.substring(0, 50)}...` : 'not changed'
        },
        existingNotes: {
          privateNotes: place.privateNotes ? `${place.privateNotes.substring(0, 50)}...` : 'empty',
          publicNotes: place.publicNotes ? `${place.publicNotes.substring(0, 50)}...` : 'empty',
          notes: place.notes ? `${place.notes.substring(0, 50)}...` : 'empty'
        }
      });
    }

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
      
      // Soft delete the place by setting deletedAt timestamp
      batch.update(placeRef, {
        deletedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
      
      // Commit the batch
      await batch.commit();
      
      console.log('✅ Place soft deleted successfully:', req.params.id);

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
    
    // Check if Google Places API key is configured
    if (!googleMapsApiKey) {
      console.log('⚠️ Google Maps API key not configured, cannot refresh place details');
      return res.status(200).json({
        success: true,
        message: 'Place data is up to date',
        place: place
      });
    }
    
    let googlePlaceId = place.googlePlaceId;
    
    // If no googlePlaceId, try to find it using place name and location
    if (!googlePlaceId && place.location && place.name) {
      console.log('🔍 No Google Place ID found, searching by name and location...');
      
      try {
        // Search for the place using text search
        const searchResponse = await googleMapsClient.findPlaceFromText({
          params: {
            input: place.name,
            inputtype: 'textquery',
            fields: ['place_id', 'name', 'geometry'],
            locationbias: place.location ? `point:${place.location.coordinates[1]},${place.location.coordinates[0]}` : undefined,
            key: googleMapsApiKey
          }
        });
        
        if (searchResponse.data.candidates && searchResponse.data.candidates.length > 0) {
          // Find the best match based on distance
          let bestMatch = searchResponse.data.candidates[0];
          
          if (place.location && searchResponse.data.candidates.length > 1) {
            const placeCoords = place.location.coordinates;
            let minDistance = Infinity;
            
            for (const candidate of searchResponse.data.candidates) {
              if (candidate.geometry && candidate.geometry.location) {
                const distance = Math.sqrt(
                  Math.pow(candidate.geometry.location.lat - placeCoords[1], 2) +
                  Math.pow(candidate.geometry.location.lng - placeCoords[0], 2)
                );
                
                if (distance < minDistance) {
                  minDistance = distance;
                  bestMatch = candidate;
                }
              }
            }
          }
          
          googlePlaceId = bestMatch.place_id;
          console.log(`✅ Found matching Google Place: ${bestMatch.name} (ID: ${googlePlaceId})`);
          
          // Update the place with the found googlePlaceId
          await placeRef.update({ googlePlaceId });
        } else {
          console.log('⚠️ No matching Google Place found');
          return res.status(200).json({
            success: true,
            message: 'Could not find a matching Google Place for this location',
            place: place
          });
        }
      } catch (searchError) {
        console.error('❌ Error searching for Google Place:', searchError);
        return res.status(200).json({
          success: true,
          message: 'Could not search for Google Place details',
          place: place
        });
      }
    } else if (!googlePlaceId) {
      console.log('ℹ️ Cannot refresh: no Google Place ID and insufficient data to search');
      return res.status(200).json({
        success: true,
        message: 'This place does not have enough information to fetch Google details',
        place: place
      });
    }
    
    try {
      console.log('🔍 Refreshing place from Google Places API:', googlePlaceId);
      
      // Fetch updated place details from Google
      const response = await googleMapsClient.placeDetails({
        params: {
          place_id: googlePlaceId,
          fields: ['name', 'rating', 'user_ratings_total', 'photos', 'formatted_address', 'formatted_phone_number', 'website', 'opening_hours'],
          key: googleMapsApiKey
        }
      });
      
      const googlePlace = response.data.result;
      console.log('✅ Fetched place details from Google:', {
        name: googlePlace.name,
        rating: googlePlace.rating,
        photosCount: googlePlace.photos?.length || 0
      });
      
      // Prepare update data
      const updateData = {
        updatedAt: new Date().toISOString()
      };
      
      // Update rating if available
      if (googlePlace.rating !== undefined) {
        updateData.rating = googlePlace.rating;
      }
      
      if (googlePlace.user_ratings_total !== undefined) {
        updateData.userRatingsTotal = googlePlace.user_ratings_total;
      }
      
      // Update photos if available and place doesn't have custom uploaded photos
      if (googlePlace.photos && googlePlace.photos.length > 0 && (!place.photos || place.photos.length === 0)) {
        // Get photo URLs (limit to 3 photos to avoid excessive API calls)
        const photoUrls = [];
        const photosToFetch = Math.min(3, googlePlace.photos.length);
        
        for (let i = 0; i < photosToFetch; i++) {
          const photo = googlePlace.photos[i];
          const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsApiKey}`;
          photoUrls.push(photoUrl);
        }
        
        if (photoUrls.length > 0) {
          updateData.photos = photoUrls;
          console.log(`📸 Added ${photoUrls.length} Google Places photos`);
        }
      }
      
      // Update the place in Firestore
      await placeRef.update(updateData);
      
      // Get the updated place
      const updatedDoc = await placeRef.get();
      const updatedPlace = serializeDoc(updatedDoc);
      
      console.log('✅ Place refreshed successfully');
      
      res.status(200).json({
        success: true,
        message: 'Place updated with latest information',
        place: updatedPlace
      });
      
    } catch (googleError) {
      console.error('❌ Google Places API error:', googleError);
      
      // Return the existing place even if refresh fails
      res.status(200).json({
        success: false,
        message: 'Could not refresh place data at this time',
        place: place
      });
    }
    
  } catch (error) {
    console.error('Error refreshing place from Google:', error);
    next(error);
  }
};

// @desc    Update place address and optionally coordinates
// @route   PUT /api/places/:id/update-address
// @access  Private (owner or circle member)
exports.updatePlaceAddress = async (req, res, next) => {
  try {
    const { address, location } = req.body;
    
    if (!address || typeof address !== 'string' || address.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Please provide a valid address'
      });
    }
    
    // Validate location if provided
    if (location) {
      if (!location.type || location.type !== 'Point' || 
          !location.coordinates || !Array.isArray(location.coordinates) ||
          location.coordinates.length !== 2) {
        return res.status(400).json({
          success: false,
          message: 'Invalid location format. Expected GeoJSON Point.'
        });
      }
      
      const [longitude, latitude] = location.coordinates;
      
      // Validate coordinates
      if (typeof longitude !== 'number' || typeof latitude !== 'number' ||
          longitude < -180 || longitude > 180 ||
          latitude < -90 || latitude > 90 ||
          (longitude === -180 && latitude === -180)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid coordinates provided'
        });
      }
    }
    
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
    const isCircleOwner = circle.owner === req.user.uid;
    const isCircleMember = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    
    if (!isOwner && !isCircleOwner && !isCircleMember) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to update this place'
      });
    }
    
    // Prepare update data
    const updateData = {
      address: address.trim(),
      updatedAt: new Date().toISOString()
    };
    
    // Add location if provided
    if (location) {
      updateData.location = location;
      console.log(`📍 Updating location for place ${req.params.id} to:`, location.coordinates);
    }
    
    // Update the place
    await placeRef.update(updateData);
    
    // Get the updated place
    const updatedDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedDoc);
    
    console.log('✅ Place address updated successfully:', {
      placeId: req.params.id,
      oldAddress: place.address,
      newAddress: address.trim()
    });
    
    res.status(200).json({
      success: true,
      place: updatedPlace
    });
    
  } catch (error) {
    console.error('Error updating place address:', error);
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
    
    // Track activity for likes (not unlikes)
    if (!alreadyLiked) {
      const { createActivity } = require('./activityController');
      await createActivity(
        'place_liked',
        userId,
        'place',
        placeId,
        place.name || 'Unknown Place',
        {
          circleId: place.circleId,
          circleName: circle.name || 'Unknown Circle',
          placePhoto: place.photos && place.photos.length > 0 ? place.photos[0] : null,
          placeAddress: place.address || null
        }
      );
    }
    
  } catch (error) {
    console.error('Error liking place:', error);
    next(error);
  }
};

// @desc    Get likes for a place
// @route   GET /api/places/:id/likes
// @access  Private
exports.getPlaceLikes = async (req, res, next) => {
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
    
    // Check if user has permission to view this place (same logic as likePlace)
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
        message: 'Not authorized to view likes for this place'
      });
    }
    
    // Get user IDs who liked this place
    const likes = place.likes || [];
    
    if (likes.length === 0) {
      return res.status(200).json({
        success: true,
        likes: [],
        count: 0
      });
    }
    
    // Fetch user details for each user who liked the place
    const userPromises = likes.map(async (likeUserId) => {
      // Handle complex ID format if needed
      let actualUserId = likeUserId;
      if (likeUserId && likeUserId.includes('.')) {
        const parts = likeUserId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1]; // Use the middle part as Firebase UID
        }
      }
      
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(actualUserId).get();
      if (userDoc.exists) {
        const userData = serializeDoc(userDoc);
        return {
          _id: userData.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          bio: userData.bio
        };
      }
      return null;
    });
    
    const users = await Promise.all(userPromises);
    const validUsers = users.filter(user => user !== null);
    
    res.status(200).json({
      success: true,
      likes: validUsers,
      count: validUsers.length
    });
    
  } catch (error) {
    console.error('Error fetching place likes:', error);
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
    
    console.log('🔍 getPlaceComments called:', {
      placeId,
      userId,
      timestamp: new Date().toISOString()
    });
    
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
    
    // Get comments (only top-level comments, not replies)
    console.log('📋 Fetching top-level comments from placeComments collection for place:', placeId);
    const commentsSnapshot = await db.collection('placeComments')
      .where('placeId', '==', placeId)
      .orderBy('createdAt', 'desc')
      .get();
    
    console.log(`✅ Found ${commentsSnapshot.size} comments for place ${placeId}`);
    
    const comments = [];
    for (const doc of commentsSnapshot.docs) {
      const comment = serializeDoc(doc);
      
      // Only include top-level comments (no parentCommentId or parentCommentId is null/undefined)
      if (!comment.parentCommentId) {
        // Get user details
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
        if (userDoc.exists) {
          comment.user = serializeDoc(userDoc);
        }
        
        // Ensure replyCount is included (default to 0 if not present)
        if (comment.replyCount === undefined || comment.replyCount === null) {
          comment.replyCount = 0;
        }
        
        comments.push(comment);
      }
    }
    
    console.log(`📤 Returning ${comments.length} comments with user details`);
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
    
    console.log('💬 addPlaceComment called:', {
      placeId,
      userId,
      text: text?.substring(0, 50) + (text?.length > 50 ? '...' : ''),
      timestamp: new Date().toISOString()
    });
    
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
    
    // Create comment using the model function
    const { createPlaceComment } = require('../models/FirestoreModels');
    const commentData = createPlaceComment({
      placeId: placeId,
      userId: userId,
      text: text.trim()
    });
    
    console.log('💾 Saving comment to placeComments collection');
    const commentRef = await db.collection('placeComments').add(commentData);
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    console.log('✅ Comment saved successfully with ID:', comment.id);
    
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
      data: comment
    });
    
    // Track comment activity
    const { createActivity } = require('./activityController');
    await createActivity(
      'place_commented',
      userId,
      'place',
      placeId,
      place.name || 'Unknown Place',
      {
        circleId: place.circleId,
        circleName: circle.name || 'Unknown Circle',
        comment: text.trim(),
        placePhoto: place.photos && place.photos.length > 0 ? place.photos[0] : null,
        placeAddress: place.address || null
      }
    );
    
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
        .where('deletedAt', '==', null)
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
        .where('deletedAt', '==', null)
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

// @desc    Delete a comment from a place
// @route   DELETE /api/places/:placeId/comments/:commentId
// @access  Private (comment owner or place owner)
exports.deletePlaceComment = async (req, res, next) => {
  try {
    const { placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    // Get the comment
    const commentRef = db.collection('placeComments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = serializeDoc(commentDoc);
    
    // Check if comment belongs to this place
    if (comment.placeId !== placeId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
      });
    }
    
    // Get the place to check ownership
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user can delete the comment
    // User can delete if they are:
    // 1. The comment author
    // 2. The place owner
    const isCommentAuthor = comment.userId === userId;
    const isPlaceOwner = place.addedBy === userId;
    
    if (!isCommentAuthor && !isPlaceOwner) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this comment'
      });
    }
    
    // Delete the comment
    await commentRef.delete();
    
    res.status(200).json({
      success: true,
      message: 'Comment deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting place comment:', error);
    next(error);
  }
};

// @desc    Like or unlike a comment
// @route   POST /api/places/:placeId/comments/:commentId/like
// @access  Private
exports.likeComment = async (req, res, next) => {
  try {
    const { placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    // Get the comment
    const commentRef = db.collection('placeComments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = serializeDoc(commentDoc);
    
    // Check if comment belongs to this place
    if (comment.placeId !== placeId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
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
    
    // Check permissions (same as viewing place)
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
    
    if (!isOwner && !isSharedWith && !isPublic && !isConnected) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to like comments on this place'
      });
    }
    
    // Toggle like
    const currentLikes = comment.likes || [];
    const alreadyLiked = currentLikes.includes(userId);
    
    let updatedLikes;
    let updatedLikesCount;
    
    if (alreadyLiked) {
      // Unlike - remove user from likes array
      updatedLikes = currentLikes.filter(id => id !== userId);
      updatedLikesCount = Math.max(0, (comment.likesCount || 0) - 1);
    } else {
      // Like - add user to likes array
      updatedLikes = [...currentLikes, userId];
      updatedLikesCount = (comment.likesCount || 0) + 1;
    }
    
    // Update comment
    await commentRef.update({
      likes: updatedLikes,
      likesCount: updatedLikesCount,
      updatedAt: new Date().toISOString()
    });
    
    // Track activity if liking (not unliking)
    if (!alreadyLiked) {
      const { createActivity } = require('./activityController');
      await createActivity(
        'comment_liked',
        userId,
        'comment',
        commentId,
        `Comment on ${place.name}`,
        {
          placeId: placeId,
          placeName: place.name,
          circleId: place.circleId,
          circleName: circle.name || 'Unknown Circle',
          commentText: comment.text,
          commentAuthorId: comment.userId
        }
      );
    }
    
    res.status(200).json({
      success: true,
      liked: !alreadyLiked,
      likesCount: updatedLikesCount
    });
    
  } catch (error) {
    console.error('Error liking/unliking comment:', error);
    next(error);
  }
};

// @desc    Add reply to a place comment
// @route   POST /api/places/:id/comments/:commentId/replies
// @access  Private
exports.addPlaceCommentReply = async (req, res, next) => {
  try {
    const { id: placeId, commentId } = req.params;
    const userId = req.user.uid;
    const { text } = req.body;
    
    console.log('💬 addPlaceCommentReply called:', {
      placeId,
      commentId,
      userId,
      text: text?.substring(0, 50) + (text?.length > 50 ? '...' : ''),
      timestamp: new Date().toISOString()
    });
    
    if (!text || text.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Reply text is required'
      });
    }
    
    // Get the parent comment to validate it exists
    const parentCommentRef = db.collection('placeComments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);
    
    // Ensure the parent comment belongs to the specified place
    if (parentComment.placeId !== placeId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
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
    
    // Check if user can reply to comments on this place (same permissions as commenting)
    // Get the circle to check permissions
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Check permissions
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
        message: 'Not authorized to reply to comments on this place'
      });
    }
    
    // Create reply data using the new model function
    const { createPlaceComment } = require('../models/FirestoreModels');
    const replyData = createPlaceComment({
      placeId: placeId,
      userId: userId,
      text: text.trim(),
      parentCommentId: commentId
    });
    
    console.log('💾 Saving reply to placeComments collection');
    const replyRef = await db.collection('placeComments').add(replyData);
    const replyDoc = await replyRef.get();
    const reply = serializeDoc(replyDoc);
    console.log('✅ Reply saved successfully with ID:', reply.id);
    
    // Get user details for the reply
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      reply.user = serializeDoc(userDoc);
    }
    
    // Update parent comment reply count
    const currentReplyCount = parentComment.replyCount || 0;
    await parentCommentRef.update({
      replyCount: currentReplyCount + 1
    });
    
    console.log('✅ Parent comment reply count updated');
    
    res.status(201).json({
      success: true,
      data: reply
    });
    
  } catch (error) {
    console.error('Error adding place comment reply:', error);
    next(error);
  }
};

// @desc    Get replies for a place comment
// @route   GET /api/places/:id/comments/:commentId/replies
// @access  Private
exports.getPlaceCommentReplies = async (req, res, next) => {
  try {
    const { id: placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    console.log('🔍 getPlaceCommentReplies called:', {
      placeId,
      commentId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Verify parent comment exists and belongs to the place
    const parentCommentRef = db.collection('placeComments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);
    
    if (parentComment.placeId !== placeId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
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
    
    // Check if user can view replies (same permissions as viewing comments)
    // Get the circle to check permissions
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Check permissions
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
        message: 'Not authorized to view replies on this place'
      });
    }
    
    // Get replies for this comment
    const repliesSnapshot = await db.collection('placeComments')
      .where('parentCommentId', '==', commentId)
      .orderBy('createdAt', 'asc') // Replies should be chronological
      .get();
    
    const replies = [];
    for (const replyDoc of repliesSnapshot.docs) {
      const reply = serializeDoc(replyDoc);
      
      // Get user details for each reply
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(reply.userId).get();
      if (userDoc.exists) {
        reply.user = serializeDoc(userDoc);
      }
      
      replies.push(reply);
    }
    
    console.log(`✅ Found ${replies.length} replies for comment ${commentId}`);
    
    // Log details of replies for debugging
    replies.forEach((reply, index) => {
      console.log(`  Reply ${index + 1}: id=${reply.id}, userId=${reply.userId}, text="${reply.text?.substring(0, 50)}..."`);
    });
    
    res.status(200).json({
      success: true,
      comments: replies
    });
    
  } catch (error) {
    console.error('Error getting place comment replies:', error);
    next(error);
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

// @desc    Move a place to a different circle
// @route   POST /api/places/:id/move
// @access  Private
exports.movePlace = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    const { targetCircleId } = req.body;
    
    if (!targetCircleId) {
      return res.status(400).json({
        success: false,
        message: 'Target circle ID is required'
      });
    }
    
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
    
    // Get source circle
    const sourceCircleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const sourceCircleDoc = await sourceCircleRef.get();
    
    if (!sourceCircleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Source circle not found'
      });
    }
    
    const sourceCircle = serializeDoc(sourceCircleDoc);
    
    // Get target circle
    const targetCircleRef = db.collection(COLLECTIONS.CIRCLES).doc(targetCircleId);
    const targetCircleDoc = await targetCircleRef.get();
    
    if (!targetCircleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Target circle not found'
      });
    }
    
    const targetCircle = serializeDoc(targetCircleDoc);
    
    // Check permissions: user must own both circles or be the place creator
    const ownsSourceCircle = sourceCircle.owner === userId;
    const ownsTargetCircle = targetCircle.owner === userId;
    const isPlaceCreator = place.addedBy === userId;
    
    if (!ownsSourceCircle || !ownsTargetCircle) {
      if (!isPlaceCreator || !ownsTargetCircle) {
        return res.status(403).json({
          success: false,
          message: 'You must own both circles or be the place creator and own the target circle to move a place'
        });
      }
    }
    
    // Check if target circle already has this place (by googlePlaceId or name+address)
    if (place.googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', targetCircleId)
        .where('googlePlaceId', '==', place.googlePlaceId)
        .where('deletedAt', '==', null)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the target circle'
        });
      }
    } else {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', targetCircleId)
        .where('name', '==', place.name)
        .where('address', '==', place.address)
        .where('deletedAt', '==', null)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the target circle'
        });
      }
    }
    
    // Use a transaction for atomic updates
    await db.runTransaction(async (transaction) => {
      // Remove place ID from source circle
      const sourcePlaces = sourceCircle.places || [];
      const updatedSourcePlaces = sourcePlaces.filter(id => id !== placeId);
      
      transaction.update(sourceCircleRef, {
        places: updatedSourcePlaces,
        placesCount: Math.max(0, (sourceCircle.placesCount || 0) - 1),
        updatedAt: new Date().toISOString()
      });
      
      // Add place ID to target circle
      const targetPlaces = targetCircle.places || [];
      transaction.update(targetCircleRef, {
        places: [placeId, ...targetPlaces], // Add at beginning
        placesCount: (targetCircle.placesCount || 0) + 1,
        updatedAt: new Date().toISOString()
      });
      
      // Update place's circleId
      transaction.update(placeRef, {
        circleId: targetCircleId,
        updatedAt: new Date().toISOString()
      });
    });
    
    // Get updated place
    const updatedPlaceDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedPlaceDoc);
    
    // Track activity
    if (trackPlaceAdded) {
      await trackPlaceAdded(placeId, targetCircleId, updatedPlace.name, targetCircle.name, userId);
    }
    
    res.status(200).json({
      success: true,
      message: 'Place moved successfully',
      place: updatedPlace
    });
    
  } catch (error) {
    console.error('Error moving place:', error);
    next(error);
  }
};

// @desc    Get places from multiple circles in a single request
// @route   POST /api/places/batch
// @access  Private
exports.getPlacesByMultipleCircles = async (req, res, next) => {
  try {
    console.log('🔍 getPlacesByMultipleCircles - START - Request details:', {
      circleIds: req.body.circleIds?.length || 0,
      userUid: req.user?.uid,
      userEmail: req.user?.email
    });

    const { circleIds } = req.body;
    
    if (!circleIds || !Array.isArray(circleIds) || circleIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Circle IDs array is required'
      });
    }
    
    // Limit the number of circles to prevent abuse
    if (circleIds.length > 50) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 50 circles allowed per batch request'
      });
    }
    
    const currentUserId = req.user.uid;
    const allPlaces = [];
    const processedCircles = new Set();
    
    // Process circles in chunks to avoid overwhelming the database
    const chunkSize = 10;
    for (let i = 0; i < circleIds.length; i += chunkSize) {
      const chunk = circleIds.slice(i, i + chunkSize);
      
      // Fetch circles in this chunk
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('__name__', 'in', chunk)
        .get();
      
      for (const circleDoc of circlesSnapshot.docs) {
        const circle = serializeDoc(circleDoc);
        
        // Skip if we've already processed this circle
        if (processedCircles.has(circle.id)) {
          continue;
        }
        processedCircles.add(circle.id);
        
        // Check permissions
        const isOwner = circle.owner === currentUserId;
        const isSharedWith = circle.sharedWith && circle.sharedWith.includes(currentUserId);
        const isPublic = circle.privacy === 'public';
        
        // For myNetwork privacy, check if users are connected
        let isConnected = false;
        if (circle.privacy === 'myNetwork' && !isOwner) {
          const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', currentUserId)
            .where('connectedUserId', '==', circle.owner)
            .where('status', '==', 'accepted')
            .limit(1)
            .get();
            
          const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', circle.owner)
            .where('connectedUserId', '==', currentUserId)
            .where('status', '==', 'accepted')
            .limit(1)
            .get();
            
          isConnected = !connection1.empty || !connection2.empty;
        }
        
        // Skip if user doesn't have access
        if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
          console.log(`⚠️ User doesn't have access to circle ${circle.id}`);
          continue;
        }
        
        // Get places from this circle
        const placeIds = circle.places || [];
        if (placeIds.length > 0) {
          // Fetch places in chunks
          const placeChunkSize = 10;
          for (let j = 0; j < placeIds.length; j += placeChunkSize) {
            const placeChunk = placeIds.slice(j, j + placeChunkSize);
            
            const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
              .where('__name__', 'in', placeChunk)
              .where('deletedAt', '==', null)
              .get();
            
            placesSnapshot.forEach(placeDoc => {
              const place = serializeDoc(placeDoc);
              // Ensure place belongs to the correct circle
              if (place.circleId === circle.id) {
                allPlaces.push(place);
              }
            });
          }
        }
      }
    }
    
    console.log(`✅ Batch fetched ${allPlaces.length} places from ${processedCircles.size} accessible circles`);
    
    res.status(200).json({
      success: true,
      places: allPlaces,
      circlesProcessed: processedCircles.size,
      totalPlaces: allPlaces.length
    });
    
  } catch (error) {
    console.error('Error in batch place fetch:', error);
    next(error);
  }
};