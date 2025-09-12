// backend/controllers/globalPlaceController.js
// Controller for global place management in normalized place architecture

const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');

const {
  GLOBAL_COLLECTIONS,
  createGlobalPlace,
  createAttributedPhoto,
  createAttributedVideo,
  createPublicReview,
  createUserPlaceRelation,
  validateGlobalPlace,
  validateUserPlaceRelation,
  validatePublicReview,
  calculateDataCompleteness,
  calculateQualityScore,
  mergeGooglePlaceData
} = require('../models/GlobalPlace');

const { serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get global place by ID with all public content
// @route   GET /api/places/global/:placeId
// @access  Private
exports.getGlobalPlace = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    
    // Get global place document
    const placeDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const placeData = serializeDoc(placeDoc);
    
    // Get user's relationship to this place if they have one
    let userRelation = null;
    if (req.user?.id) {
      const relationQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
        .where('userId', '==', req.user.id)
        .where('placeId', '==', placeId)
        .limit(1)
        .get();
      
      if (!relationQuery.empty) {
        userRelation = serializeDoc(relationQuery.docs[0]);
      }
    }
    
    // Populate user information for public reviews
    if (placeData.publicReviews && placeData.publicReviews.length > 0) {
      const userIds = [...new Set(placeData.publicReviews.map(review => review.userId))];
      
      // Get user information for reviewers
      const usersQuery = await db.collection('users')
        .where(admin.firestore.FieldPath.documentId(), 'in', userIds.slice(0, 10)) // Limit to prevent query size issues
        .get();
      
      const usersMap = {};
      usersQuery.docs.forEach(doc => {
        const userData = doc.data();
        usersMap[doc.id] = {
          id: doc.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture
        };
      });
      
      // Populate user info in reviews
      placeData.publicReviews = placeData.publicReviews.map(review => ({
        ...review,
        userName: usersMap[review.userId]?.displayName || review.userName || 'Unknown User',
        userPhoto: usersMap[review.userId]?.profilePicture || review.userPhoto
      }));
    }
    
    res.status(200).json({
      success: true,
      data: {
        globalPlace: placeData,
        userRelation: userRelation
      }
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Search global places
// @route   GET /api/places/global/search
// @access  Private
exports.searchGlobalPlaces = async (req, res, next) => {
  try {
    const { 
      query, 
      category, 
      lat, 
      lng, 
      radius = 50, // km
      limit = 20,
      offset = 0 
    } = req.query;
    
    let placesQuery = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES);
    
    // Filter by category if provided
    if (category && category !== 'all') {
      placesQuery = placesQuery.where('category', '==', category);
    }
    
    // Text search on name (simple contains - in production would use Algolia/Elasticsearch)
    if (query && query.trim()) {
      // Note: Firestore doesn't have full-text search, so this is a basic implementation
      // In production, we'd use a search service like Algolia
      const queryLower = query.toLowerCase();
      placesQuery = placesQuery
        .where('name', '>=', queryLower)
        .where('name', '<=', queryLower + '\uf8ff');
    }
    
    // Order by quality score for best results first
    placesQuery = placesQuery
      .orderBy('qualityScore', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset));
    
    const placesSnapshot = await placesQuery.get();
    let places = serializeQuerySnapshot(placesSnapshot);
    
    // Apply geolocation filtering if provided
    if (lat && lng) {
      const centerLat = parseFloat(lat);
      const centerLng = parseFloat(lng);
      const maxRadius = parseFloat(radius);
      
      places = places.filter(place => {
        if (!place.location || !place.location.coordinates) return false;
        
        const [placeLng, placeLat] = place.location.coordinates;
        const distance = calculateDistance(centerLat, centerLng, placeLat, placeLng);
        
        return distance <= maxRadius;
      });
      
      // Sort by distance if geo-filtering
      places = places.sort((a, b) => {
        const distanceA = calculateDistance(centerLat, centerLng, 
          a.location.coordinates[1], a.location.coordinates[0]);
        const distanceB = calculateDistance(centerLat, centerLng, 
          b.location.coordinates[1], b.location.coordinates[0]);
        return distanceA - distanceB;
      });
    }
    
    res.status(200).json({
      success: true,
      data: places,
      total: places.length,
      hasMore: places.length === parseInt(limit)
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Create or get global place
// @route   POST /api/places/global
// @access  Private
exports.createOrGetGlobalPlace = async (req, res, next) => {
  try {
    const placeData = req.body;
    
    // Check if place already exists by Google Place ID
    let existingPlace = null;
    if (placeData.googlePlaceId) {
      const existingQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
        .where('googlePlaceId', '==', placeData.googlePlaceId)
        .limit(1)
        .get();
      
      if (!existingQuery.empty) {
        existingPlace = serializeDoc(existingQuery.docs[0]);
      }
    }
    
    if (existingPlace) {
      // Place already exists, return it
      res.status(200).json({
        success: true,
        data: existingPlace,
        created: false,
        message: 'Place already exists'
      });
    } else {
      // Create new global place
      const validationErrors = validateGlobalPlace(placeData);
      if (validationErrors.length > 0) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: validationErrors
        });
      }
      
      const globalPlace = createGlobalPlace(placeData);
      
      // Calculate initial quality scores
      globalPlace.dataCompleteness = calculateDataCompleteness(globalPlace);
      globalPlace.qualityScore = calculateQualityScore(globalPlace);
      
      // Save to database
      const docRef = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).add(globalPlace);
      const newPlace = await docRef.get();
      
      res.status(201).json({
        success: true,
        data: serializeDoc(newPlace),
        created: true,
        message: 'Global place created successfully'
      });
    }
  } catch (error) {
    next(error);
  }
};

// @desc    Add user-place relationship (add place to user's circle)
// @route   POST /api/places/global/:placeId/relations
// @access  Private
exports.createUserPlaceRelation = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    const relationData = {
      ...req.body,
      userId: req.user.id,
      placeId: placeId
    };
    
    // Validate relation data
    const validationErrors = validateUserPlaceRelation(relationData);
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: validationErrors
      });
    }
    
    // Check if relation already exists
    const existingQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
      .where('userId', '==', req.user.id)
      .where('placeId', '==', placeId)
      .where('circleId', '==', relationData.circleId)
      .limit(1)
      .get();
    
    if (!existingQuery.empty) {
      return res.status(409).json({
        success: false,
        message: 'Place already added to this circle'
      });
    }
    
    // Create the relation
    const userPlaceRelation = createUserPlaceRelation(relationData);
    
    // Save relation
    const docRef = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS).add(userPlaceRelation);
    const newRelation = await docRef.get();
    
    // Update global place statistics
    await updateGlobalPlaceStats(placeId);
    
    res.status(201).json({
      success: true,
      data: serializeDoc(newRelation),
      message: 'Place added to circle successfully'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Add public review to global place
// @route   POST /api/places/global/:placeId/reviews
// @access  Private
exports.addPublicReview = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    const reviewData = {
      ...req.body,
      userId: req.user.id,
      userName: req.user.displayName,
      userPhoto: req.user.profilePicture
    };
    
    // Validate review data
    const validationErrors = validatePublicReview(reviewData);
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: validationErrors
      });
    }
    
    // Check if place exists
    const placeDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    // Create the review
    const publicReview = createPublicReview(reviewData);
    
    // Add review to place's publicReviews array
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update({
      publicReviews: admin.firestore.FieldValue.arrayUnion(publicReview),
      'userContributions.totalReviews': admin.firestore.FieldValue.increment(1),
      'userContributions.contributors': admin.firestore.FieldValue.arrayUnion(req.user.id),
      lastActivityAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Update quality score
    await updateGlobalPlaceStats(placeId);
    
    res.status(201).json({
      success: true,
      data: publicReview,
      message: 'Review added successfully'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Upload media to global place
// @route   POST /api/places/global/:placeId/media
// @access  Private
exports.uploadPlaceMedia = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    const { mediaType, mediaUrl, thumbnailUrl, title, description, source = 'user_upload' } = req.body;
    
    // Check if place exists
    const placeDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    let attributedMedia;
    let updateField;
    let incrementField;
    
    if (mediaType === 'photo') {
      attributedMedia = createAttributedPhoto({
        url: mediaUrl,
        uploadedBy: req.user.id,
        uploadedByName: req.user.displayName,
        source: source
      });
      updateField = 'photos';
      incrementField = 'userContributions.totalPhotos';
    } else if (mediaType === 'video') {
      attributedMedia = createAttributedVideo({
        videoUrl: mediaUrl,
        thumbnailUrl: thumbnailUrl,
        uploadedBy: req.user.id,
        uploadedByName: req.user.displayName,
        title: title || '',
        description: description || ''
      });
      updateField = 'videos';
      incrementField = 'userContributions.totalVideos';
    } else {
      return res.status(400).json({
        success: false,
        message: 'Invalid media type. Must be "photo" or "video"'
      });
    }
    
    // Add media to place
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update({
      [updateField]: admin.firestore.FieldValue.arrayUnion(attributedMedia),
      [incrementField]: admin.firestore.FieldValue.increment(1),
      'userContributions.contributors': admin.firestore.FieldValue.arrayUnion(req.user.id),
      lastActivityAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Update quality score
    await updateGlobalPlaceStats(placeId);
    
    res.status(201).json({
      success: true,
      data: attributedMedia,
      message: `${mediaType} uploaded successfully`
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Get user's relationship to a place
// @route   GET /api/places/global/:placeId/user-relation
// @access  Private
exports.getUserPlaceRelation = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    const userId = req.user.id;
    
    const relationQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
      .where('userId', '==', userId)
      .where('placeId', '==', placeId)
      .get();
    
    const relations = serializeQuerySnapshot(relationQuery);
    
    res.status(200).json({
      success: true,
      data: relations
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Update user-place relationship
// @route   PUT /api/places/global/:placeId/relations/:relationId
// @access  Private
exports.updateUserPlaceRelation = async (req, res, next) => {
  try {
    const { placeId, relationId } = req.params;
    const updateData = req.body;
    
    // Verify the relation belongs to the current user
    const relationDoc = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS).doc(relationId).get();
    
    if (!relationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Relation not found'
      });
    }
    
    const relationData = relationDoc.data();
    if (relationData.userId !== req.user.id) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this relation'
      });
    }
    
    // Update the relation
    const updates = {
      ...updateData,
      updatedAt: new Date().toISOString()
    };
    
    await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS).doc(relationId).update(updates);
    
    // Get updated relation
    const updatedDoc = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS).doc(relationId).get();
    
    res.status(200).json({
      success: true,
      data: serializeDoc(updatedDoc),
      message: 'Relation updated successfully'
    });
  } catch (error) {
    next(error);
  }
};

// Helper function to update global place statistics
async function updateGlobalPlaceStats(placeId) {
  const placeDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
  
  if (placeDoc.exists) {
    const placeData = placeDoc.data();
    
    // Recalculate quality scores
    const dataCompleteness = calculateDataCompleteness(placeData);
    const qualityScore = calculateQualityScore(placeData);
    
    // Count total references
    const relationsQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
      .where('placeId', '==', placeId)
      .get();
    
    const totalReferences = relationsQuery.size;
    const uniqueUsers = [...new Set(relationsQuery.docs.map(doc => doc.data().userId))].length;
    
    // Update place with new stats
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update({
      dataCompleteness: dataCompleteness,
      qualityScore: qualityScore,
      totalCircleReferences: totalReferences,
      totalUserReferences: uniqueUsers,
      updatedAt: new Date().toISOString()
    });
  }
}

// Helper function to calculate distance between two points
function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng/2) * Math.sin(dLng/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

module.exports = {
  getGlobalPlace,
  searchGlobalPlaces,
  createOrGetGlobalPlace,
  createUserPlaceRelation,
  addPublicReview,
  uploadPlaceMedia,
  getUserPlaceRelation,
  updateUserPlaceRelation,
  updateGlobalPlaceStats
};