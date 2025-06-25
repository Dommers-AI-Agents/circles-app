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
    
    // Check permissions
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith.includes(req.user.uid);
    const isPublic = circle.privacy === 'public';
    
    if (!isOwner && !isSharedWith && !isPublic) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }

    // Get places for this circle
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .get();

    const places = serializeQuerySnapshot(placesSnapshot);
    
    // Create a map for quick lookup
    const placesMap = new Map();
    places.forEach(place => {
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
      orderedPlaces = places.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    
    console.log('Circle places order:', circle.places || []);
    console.log('Returning places in order:', orderedPlaces.map(p => ({ id: p.id, name: p.name })));

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

    // Create place data
    const placeData = createPlace(req.body, circleId, req.user.uid);
    
    // Add to Firestore
    const placeRef = await db.collection(COLLECTIONS.PLACES).add(placeData);
    
    // Get the created place with ID
    const createdPlace = await placeRef.get();
    const place = serializeDoc(createdPlace);

    // Update circle's places array (only add if place.id is defined)
    const currentPlaces = circle.places || [];
    if (place.id) {
      await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
        places: [...currentPlaces, place.id],
        updatedAt: new Date().toISOString()
      });
    }

    res.status(201).json({
      success: true,
      place: place
    });
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

    // Remove place from circle's places array
    const currentPlaces = circle.places || [];
    const updatedPlaces = currentPlaces.filter(placeId => placeId !== req.params.id);
    
    await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).update({
      places: updatedPlaces,
      updatedAt: new Date().toISOString()
    });

    // Delete the place
    await placeRef.delete();

    res.status(200).json({
      success: true,
      message: 'Place deleted successfully'
    });
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