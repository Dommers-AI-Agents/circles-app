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
  mergeGooglePlaceData,
  generatePlaceKey
} = require('../models/GlobalPlace');

const { serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');

const db = getFirestore();

const { resolveGlobalPlace, createGlobalPlaceFromLegacy } = require('../services/globalPlaceResolver');


// Mirror an uploaded media URL into the legacy places docs so legacy readers
// (GET /places/:id, batch, older app builds) stay consistent. Never throws.
async function mirrorMediaToLegacyPlaces(legacyIds, field, mediaUrl) {
  for (const id of legacyIds) {
    try {
      await db.collection('places').doc(id).update({
        [field]: admin.firestore.FieldValue.arrayUnion(mediaUrl),
        updatedAt: new Date().toISOString()
      });
      console.log(`🔁 [GlobalPlace] Mirrored ${field} to legacy places/${id}`);
    } catch (e) {
      console.error(`⚠️ [GlobalPlace] Legacy ${field} mirror failed for places/${id}:`, e.message);
    }
  }
}

// Remove a photo URL from the legacy places docs (arrayRemove can't match object
// entries, so filter manually). Never throws.
async function removePhotoFromLegacyPlaces(legacyIds, photoUrl) {
  for (const id of legacyIds) {
    try {
      const doc = await db.collection('places').doc(id).get();
      if (!doc.exists) continue;
      const photos = doc.data().photos || [];
      const filtered = photos.filter(p => (typeof p === 'string' ? p : p?.url) !== photoUrl);
      if (filtered.length !== photos.length) {
        await doc.ref.update({ photos: filtered, updatedAt: new Date().toISOString() });
        console.log(`🔁 [GlobalPlace] Removed photo from legacy places/${id}`);
      }
    } catch (e) {
      console.error(`⚠️ [GlobalPlace] Legacy photo removal failed for places/${id}:`, e.message);
    }
  }
}

// @desc    Does this venue already exist in our canonical database? Called by
//          the app BEFORE fetching photos from Google Places, so a duplicate
//          add (another user already saved this venue) reuses the canonical
//          record's photos and googlePlaceId instead of re-querying Google.
//          Match: exact nameLower + coordinate proximity (Apple Maps supplies
//          name/coords before any Google call), with a normalized-address
//          fallback when no coordinates are sent.
// @route   GET /api/places/global/match?name=&lat=&lng=&address=
// @access  Private
exports.matchGlobalPlace = async (req, res) => {
  try {
    const { name, address } = req.query;
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const hasCoords = Number.isFinite(lat) && Number.isFinite(lng);

    if (!name || !name.trim()) {
      return res.status(400).json({ success: false, message: 'name is required' });
    }

    // Query by searchTokens (word-prefix tokens, same as global search) —
    // robust against whitespace/punctuation quirks in stored names, which an
    // exact nameLower equality is not. Candidates are then confirmed by
    // normalized-name equality + proximity in memory.
    const normalizeName = (n) => String(n || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean).join(' ');
    const normalizedQueryName = normalizeName(name);
    const queryWords = normalizedQueryName.split(' ');
    const longestWord = queryWords.slice().sort((a, b) => b.length - a.length)[0];
    if (!longestWord) {
      return res.json({ success: true, data: { match: null } });
    }

    const snapshot = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .where('searchTokens', 'array-contains', longestWord.slice(0, 20))
      .limit(50)
      .get();

    const geofire = require('geofire-common');
    const normalizeAddress = (a) => String(a || '').toLowerCase().trim().replace(/[^\w\s,]/g, '');
    const MAX_DISTANCE_METERS = 250;

    let match = null;
    for (const doc of snapshot.docs) {
      const place = { id: doc.id, ...doc.data() };
      if (place.deletedAt) continue;
      if (normalizeName(place.name) !== normalizedQueryName) continue;

      const coords = place.location?.coordinates; // GeoJSON [lng, lat]
      if (hasCoords && Array.isArray(coords) && coords.length === 2) {
        const distanceM = geofire.distanceBetween([lat, lng], [coords[1], coords[0]]) * 1000;
        if (distanceM <= MAX_DISTANCE_METERS) { match = place; break; }
      } else if (address && normalizeAddress(place.address) === normalizeAddress(address)) {
        match = place;
        break;
      }
    }

    if (!match) {
      return res.json({ success: true, data: { match: null } });
    }

    res.json({
      success: true,
      data: {
        match: {
          globalPlaceId: match.id,
          googlePlaceId: match.googlePlaceId || null,
          name: match.name,
          address: match.address || null,
          category: match.category || null,
          // Firebase Storage URLs — safe for the new save doc to reference
          photos: (match.photos || []).map((p) => (typeof p === 'string' ? p : p?.url)).filter(Boolean)
        }
      }
    });
  } catch (error) {
    console.error('❌ [GlobalPlace] match lookup failed:', error);
    res.status(500).json({ success: false, message: 'Match lookup failed' });
  }
};

// @desc    Get global place by ID with all public content
// @route   GET /api/places/global/:placeId
// @access  Private
exports.getGlobalPlace = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    console.log(`🔍 [GlobalPlace API] Starting lookup for placeId: ${placeId}`);
    
    // Resolve global place: direct id -> legacy id mapping -> dedup key -> google id
    const { globalPlaceDoc: placeDoc } = await resolveGlobalPlace(placeId);
    console.log(`📍 [GlobalPlace API] Resolution result: ${placeDoc ? `FOUND (${placeDoc.id})` : 'NOT FOUND'}`);

    if (!placeDoc || !placeDoc.exists) {
      console.log(`❌ [GlobalPlace API] Final result: NO PLACE FOUND for ${placeId}`);
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const placeData = serializeDoc(placeDoc);
    console.log(`✅ [GlobalPlace API] Successfully found place: "${placeData.name}" (ID: ${placeDoc.id})`);
    console.log(`📷 [GlobalPlace API] Returning ${placeData.photos?.length || 0} photos with attribution`);
    
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
    
    console.log(`🚀 [GlobalPlace API] Sending response for "${placeData.name}"`);
    if (placeData.photos && placeData.photos.length > 0) {
      console.log(`📸 [GlobalPlace API] Sample attribution: "${placeData.photos[0].uploadedByName || 'Unknown'}"`);
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
    
    // Text search via word-prefix tokens (searchTokens on each doc): matches
    // any word in the name ("pizza" finds "Colvitto's Pizza & Bakery").
    // Firestore allows one array-contains per query, so anchor on the most
    // selective (longest) token and filter the remaining tokens in memory.
    let queryTokens = [];
    if (query && query.trim()) {
      queryTokens = query.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean).map(t => t.slice(0, 20));
      if (queryTokens.length > 0) {
        const anchor = queryTokens.reduce((a, b) => (b.length > a.length ? b : a));
        placesQuery = placesQuery.where('searchTokens', 'array-contains', anchor);
      }
    }
    
    // Order by quality score for best results first
    placesQuery = placesQuery
      .orderBy('qualityScore', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset));
    
    const placesSnapshot = await placesQuery.get();
    let places = serializeQuerySnapshot(placesSnapshot);

    // Every query token must match, not just the anchored one
    if (queryTokens.length > 1) {
      places = places.filter(place =>
        queryTokens.every(token => (place.searchTokens || []).includes(token))
      );
    }

    // Internal search fields don't belong in the response payload
    places = places.map(({ searchTokens, nameLower, ...rest }) => rest);

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

    // Resolve the target globalPlaces doc (the app may pass a legacy place id).
    // If only the legacy place exists, auto-create its global doc so the upload
    // always has a durable home.
    const { globalPlaceDoc, legacyPlaceDoc } = await resolveGlobalPlace(placeId);
    let resolvedId;
    let resolvedData;
    if (globalPlaceDoc) {
      resolvedId = globalPlaceDoc.id;
      resolvedData = globalPlaceDoc.data();
    } else if (legacyPlaceDoc && legacyPlaceDoc.exists) {
      ({ resolvedId, resolvedData } = await createGlobalPlaceFromLegacy(legacyPlaceDoc));
    } else {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    console.log(`🆔 [UploadMedia] Resolved ${placeId} -> globalPlaces/${resolvedId}`);
    
    let attributedMedia;
    let updateField;
    let incrementField;
    
    if (mediaType === 'photo') {
      // Use standard ISO timestamp for compatibility
      const uploadedAt = new Date().toISOString();
      
      attributedMedia = createAttributedPhoto({
        url: mediaUrl,
        uploadedBy: req.user.id,
        uploadedByName: req.user.displayName,
        source: source,
        uploadedAt: uploadedAt
      });
      updateField = 'photos';
      incrementField = 'userContributions.totalPhotos';
      
      console.log(`📸 [UploadMedia] Creating photo for place ${placeId}:`);
      console.log(`📸 [UploadMedia] - Photo ID: ${attributedMedia.id}`);
      console.log(`📸 [UploadMedia] - Photo URL: ${mediaUrl}`);
      console.log(`📸 [UploadMedia] - Uploaded by: ${req.user.displayName} (${req.user.id})`);
      console.log(`📸 [UploadMedia] - Timestamp: ${attributedMedia.uploadedAt}`);
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
    
    // Get current photo count before update
    const beforeUpdate = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).get();
    const beforePhotoCount = beforeUpdate.data()?.photos?.length || 0;
    console.log(`📊 [UploadMedia] Photos before update: ${beforePhotoCount}`);

    // Add media to place
    console.log(`🔄 [UploadMedia] Adding ${mediaType} to ${updateField} array using arrayUnion...`);
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).update({
      [updateField]: admin.firestore.FieldValue.arrayUnion(attributedMedia),
      [incrementField]: admin.firestore.FieldValue.increment(1),
      'userContributions.contributors': admin.firestore.FieldValue.arrayUnion(req.user.id),
      lastActivityAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    // Mirror into the legacy places docs so legacy readers (GET /places/:id,
    // batch, older app builds) see the new media too
    const legacyMirrorIds = new Set(resolvedData.legacyPlaceIds || []);
    if (legacyPlaceDoc && legacyPlaceDoc.exists) legacyMirrorIds.add(legacyPlaceDoc.id);
    await mirrorMediaToLegacyPlaces([...legacyMirrorIds], updateField, mediaUrl);

    // Verify the update worked
    const afterUpdate = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).get();
    const afterPhotoCount = afterUpdate.data()?.photos?.length || 0;
    const allPhotos = afterUpdate.data()?.photos || [];
    console.log(`📊 [UploadMedia] Photos after update: ${afterPhotoCount}`);
    console.log(`✅ [UploadMedia] Photo count changed from ${beforePhotoCount} to ${afterPhotoCount}`);
    
    // Check if our specific photo was added
    const ourPhotoAdded = allPhotos.find(photo => photo.id === attributedMedia.id);
    if (ourPhotoAdded) {
      console.log(`🎯 [UploadMedia] ✅ Confirmed our photo with ID ${attributedMedia.id} was added successfully`);
    } else {
      console.log(`🚨 [UploadMedia] ❌ WARNING: Our photo with ID ${attributedMedia.id} was NOT found in the photos array!`);
      console.log(`🚨 [UploadMedia] Current photo IDs: ${allPhotos.map(p => p.id).join(', ')}`);
    }
    
    // Update quality score
    await updateGlobalPlaceStats(resolvedId);

    // Track photo upload activity (only for photos, not videos)
    if (mediaType === 'photo') {
      try {
        const placeName = resolvedData.name || 'Unknown Place';

        console.log(`🎯 [UploadMedia] Tracking photo upload activity...`);
        console.log(`🎯 [UploadMedia] - Photo ID: ${attributedMedia.id}`);
        console.log(`🎯 [UploadMedia] - Place: ${placeName} (${resolvedId})`);

        await trackPhotoUploaded(
          attributedMedia.id,
          resolvedId,
          placeName,
          mediaUrl,
          req.user.id
        );
        
        console.log(`✅ [UploadMedia] Photo upload activity tracked successfully`);
      } catch (activityError) {
        console.error('❌ [UploadMedia] Failed to track photo upload activity:', activityError);
        // Don't fail the upload if activity tracking fails
      }
    }
    
    console.log(`📤 [UploadMedia] Sending response with photo ID: ${attributedMedia.id}`);
    
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

// @desc    Get all images uploaded by a user to Global Places
// @route   GET /api/users/:userId/uploads
// @access  Private
exports.getUserUploads = async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    console.log(`🔍 [GlobalPlace API] Getting uploads for user: ${userId}`);
    console.log(`📊 [GlobalPlace API] Limit: ${limit}, Offset: ${offset}`);
    
    // Query all global places to find user's photos
    // We'll filter in memory to avoid complex index requirements
    const globalPlacesQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .orderBy('updatedAt', 'desc')
      .limit(500) // Reasonable limit to avoid loading too much data
      .get();
    
    console.log(`📍 [GlobalPlace API] Found ${globalPlacesQuery.size} global places with user photos`);
    
    // Extract user's photos from global places
    let userUploads = [];
    
    for (const placeDoc of globalPlacesQuery.docs) {
      const placeData = placeDoc.data();
      const placePhotos = placeData.photos || [];
      
      // Filter photos uploaded by this user
      const userPhotos = placePhotos.filter(photo => 
        photo.uploadedBy === userId
      );
      
      // Add place context to each photo
      userPhotos.forEach(photo => {
        userUploads.push({
          _id: photo.id || `${placeDoc.id}_${photo.url.hashCode || Date.now()}`,
          url: photo.url,
          place_name: placeData.name,
          place_id: placeDoc.id,
          uploaded_at: photo.uploadedAt,
          width: photo.width,
          height: photo.height,
          file_size: photo.fileSize,
          place_address: placeData.address,
          place_category: placeData.category
        });
      });
    }
    
    // Sort by upload date (newest first)
    userUploads.sort((a, b) => {
      const dateA = new Date(a.uploaded_at);
      const dateB = new Date(b.uploaded_at);
      return dateB - dateA;
    });
    
    // Apply pagination
    const startIndex = parseInt(offset);
    const endIndex = startIndex + parseInt(limit);
    const paginatedUploads = userUploads.slice(startIndex, endIndex);
    
    const hasMore = userUploads.length > endIndex;
    
    console.log(`📸 [GlobalPlace API] Returning ${paginatedUploads.length} uploads (total: ${userUploads.length})`);
    
    res.status(200).json({
      success: true,
      data: paginatedUploads,
      total: userUploads.length,
      has_more: hasMore
    });
    
  } catch (error) {
    console.error('❌ [GlobalPlace API] Error getting user uploads:', error);
    next(error);
  }
};

// @desc    Get photos debug info for a Global Place
// @route   GET /api/places/global/:placeId/photos-debug
// @access  Private  
exports.getPhotosDebug = async (req, res, next) => {
  try {
    const placeId = req.params.placeId;
    
    // Get place document
    const placeDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const placeData = placeDoc.data();
    const photos = placeData.photos || [];
    
    console.log(`🔍 [PhotosDebug] Place ${placeId} (${placeData.name}) has ${photos.length} photos:`);
    photos.forEach((photo, index) => {
      console.log(`🔍 [PhotosDebug] Photo ${index + 1}: ID=${photo.id}, URL=${photo.url}, UploadedBy=${photo.uploadedBy}, Timestamp=${photo.uploadedAt}`);
    });
    
    res.status(200).json({
      success: true,
      data: {
        placeId: placeId,
        placeName: placeData.name,
        totalPhotos: photos.length,
        photos: photos.map(photo => ({
          id: photo.id,
          url: photo.url,
          uploadedBy: photo.uploadedBy,
          uploadedByName: photo.uploadedByName,
          uploadedAt: photo.uploadedAt,
          source: photo.source
        }))
      }
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Delete a user's photo from a Global Place
// @route   DELETE /api/places/global/:placeId/media/:photoId
// @access  Private
exports.deleteUserPhoto = async (req, res, next) => {
  try {
    const { placeId, photoId } = req.params;
    // protect middleware populates req.user (there is no req.userId)
    const currentUserId = req.user.id;
    
    console.log(`🗑️ [GlobalPlace API] Deleting photo ${photoId} from place ${placeId} for user ${currentUserId}`);

    // Resolve the global place (the app may pass a legacy place id)
    const { globalPlaceDoc: placeDoc, legacyPlaceDoc } = await resolveGlobalPlace(placeId);

    if (!placeDoc || !placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    const resolvedId = placeDoc.id;

    const placeData = placeDoc.data();
    const photos = placeData.photos || [];
    
    // Find the photo to delete and verify ownership
    const photoIndex = photos.findIndex(photo => 
      (photo.id === photoId || photo.url.includes(photoId)) && 
      photo.uploadedBy === currentUserId
    );
    
    if (photoIndex === -1) {
      return res.status(404).json({
        success: false,
        message: 'Photo not found or not owned by user'
      });
    }
    
    const photoToDelete = photos[photoIndex];
    console.log(`📸 [GlobalPlace API] Found photo to delete: ${photoToDelete.url}`);
    
    // Remove photo from array
    photos.splice(photoIndex, 1);

    // Update place document
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).update({
      photos: photos,
      'userContributions.totalPhotos': Math.max(0, (placeData.userContributions?.totalPhotos || 1) - 1),
      updatedAt: new Date().toISOString()
    });

    // Remove the mirrored copy from the legacy places docs, or the merged
    // carousel would resurrect the deleted photo from place.photos
    const legacyRemoveIds = new Set(placeData.legacyPlaceIds || []);
    if (legacyPlaceDoc && legacyPlaceDoc.exists) legacyRemoveIds.add(legacyPlaceDoc.id);
    await removePhotoFromLegacyPlaces([...legacyRemoveIds], photoToDelete.url);

    // Update place statistics
    await updateGlobalPlaceStats(resolvedId);

    console.log(`✅ [GlobalPlace API] Successfully deleted photo ${photoId} from place ${resolvedId}`);
    
    res.status(200).json({
      success: true,
      data: 'Photo deleted successfully',
      message: 'Photo removed from place'
    });
    
  } catch (error) {
    console.error('❌ [GlobalPlace API] Error deleting user photo:', error);
    next(error);
  }
};

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

// Import activity tracking
const { trackGlobalPlaceLiked, trackPhotoUploaded } = require('../services/activityService');

// @desc    Like a Global Place upload (photo)
// @route   POST /api/places/global/:placeId/media/:photoId/like
// @access  Private
exports.likeGlobalPlaceUpload = async (req, res, next) => {
  try {
    const { placeId, photoId } = req.params;
    // protect middleware populates req.user (there is no req.user.uid contract here)
    const userId = req.user.id;

    console.log(`👍 [GlobalPlace API] User ${userId} attempting to like photo ${photoId} in place ${placeId}`);

    // Resolve the global place (the app may pass a legacy place id)
    const { globalPlaceDoc: placeDoc } = await resolveGlobalPlace(placeId);
    if (!placeDoc || !placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Global place not found'
      });
    }
    const resolvedId = placeDoc.id;

    const placeData = placeDoc.data();
    const photos = placeData.photos || [];

    // Find the photo
    const photo = photos.find(p => p.id === photoId);
    if (!photo) {
      return res.status(404).json({
        success: false,
        message: 'Photo not found'
      });
    }

    // Idempotent: liking an already-liked photo is a no-op success
    const likes = photo.likes || [];
    if (likes.includes(userId)) {
      return res.status(200).json({
        success: true,
        message: 'Photo already liked',
        likesCount: likes.length
      });
    }

    // Add like
    const updatedLikes = [...likes, userId];
    const updatedPhotos = photos.map(p =>
      p.id === photoId
        ? { ...p, likes: updatedLikes, likesCount: updatedLikes.length }
        : p
    );

    // Update the place document
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).update({
      photos: updatedPhotos,
      updatedAt: new Date().toISOString()
    });

    // Track comprehensive activity (includes connection notifications)
    if (photo.uploadedBy && photo.uploadedBy !== userId) {
      await trackGlobalPlaceLiked(
        photoId,
        resolvedId,
        placeData.name || 'Unknown Place',
        userId,
        photo.uploadedBy
      );
    }
    
    console.log(`✅ [GlobalPlace API] Successfully liked photo ${photoId}`);
    
    res.status(200).json({
      success: true,
      message: 'Photo liked successfully',
      likesCount: updatedLikes.length
    });
    
  } catch (error) {
    console.error('❌ [GlobalPlace API] Error liking Global Place upload:', error);
    next(error);
  }
};

// @desc    Unlike a Global Place upload (photo)
// @route   DELETE /api/places/global/:placeId/media/:photoId/like
// @access  Private
exports.unlikeGlobalPlaceUpload = async (req, res, next) => {
  try {
    const { placeId, photoId } = req.params;
    // protect middleware populates req.user (there is no req.user.uid contract here)
    const userId = req.user.id;

    console.log(`👎 [GlobalPlace API] User ${userId} attempting to unlike photo ${photoId} in place ${placeId}`);

    // Resolve the global place (the app may pass a legacy place id)
    const { globalPlaceDoc: placeDoc } = await resolveGlobalPlace(placeId);
    if (!placeDoc || !placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Global place not found'
      });
    }
    const resolvedId = placeDoc.id;

    const placeData = placeDoc.data();
    const photos = placeData.photos || [];

    // Find the photo
    const photo = photos.find(p => p.id === photoId);
    if (!photo) {
      return res.status(404).json({
        success: false,
        message: 'Photo not found'
      });
    }

    // Idempotent: unliking a not-liked photo is a no-op success
    const likes = photo.likes || [];
    if (!likes.includes(userId)) {
      return res.status(200).json({
        success: true,
        message: 'Photo not liked',
        likesCount: likes.length
      });
    }

    // Remove like
    const updatedLikes = likes.filter(id => id !== userId);
    const updatedPhotos = photos.map(p =>
      p.id === photoId
        ? { ...p, likes: updatedLikes, likesCount: updatedLikes.length }
        : p
    );

    // Update the place document
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(resolvedId).update({
      photos: updatedPhotos,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`✅ [GlobalPlace API] Successfully unliked photo ${photoId}`);
    
    res.status(200).json({
      success: true,
      message: 'Photo unliked successfully',
      likesCount: updatedLikes.length
    });
    
  } catch (error) {
    console.error('❌ [GlobalPlace API] Error unliking Global Place upload:', error);
    next(error);
  }
};

// Functions are already exported using exports.functionName above