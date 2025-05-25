// backend/controllers/firebasePlaceController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createPlace, 
  validatePlace,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');

const db = getFirestore();

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
    
    // Sort in memory for now
    places.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    res.status(200).json({
      success: true,
      count: places.length,
      places: places
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