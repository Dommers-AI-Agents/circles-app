// backend/services/placeTransitionService.js
// Service to handle transition between legacy place system and new global places architecture

const { getFirestore } = require('../config/firebase');
const admin = require('firebase-admin');

const {
  GLOBAL_COLLECTIONS,
  createGlobalPlace,
  createUserPlaceRelation,
  createAttributedPhoto,
  createAttributedVideo,
  createPublicReview,
  calculateDataCompleteness,
  calculateQualityScore
} = require('../models/GlobalPlace');

const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');

const db = getFirestore();

// Configuration for gradual rollout
const FEATURE_FLAGS = {
  USE_GLOBAL_PLACES_READ: process.env.USE_GLOBAL_PLACES_READ === 'true',
  USE_GLOBAL_PLACES_WRITE: process.env.USE_GLOBAL_PLACES_WRITE === 'true',
  MIGRATION_MODE: process.env.MIGRATION_MODE === 'true' // Writes to both systems
};

// Generate consistent place key for deduplication (matches migration script)
function generatePlaceKey(place) {
  if (place.googlePlaceId && place.googlePlaceId.trim()) {
    return `google:${place.googlePlaceId}`;
  }
  
  const normalizedName = place.name.toLowerCase().trim().replace(/[^\w\s]/g, '');
  const normalizedAddress = place.address.toLowerCase().trim().replace(/[^\w\s,]/g, '');
  
  return `manual:${normalizedName}:${normalizedAddress}`;
}

// Get places for a circle - supports both legacy and global systems
async function getCirclePlaces(circleId, userId, options = {}) {
  const { includeUserRelations = false, includePublicContent = false } = options;
  
  try {
    if (FEATURE_FLAGS.USE_GLOBAL_PLACES_READ) {
      // Use new global places system
      return await getCirclePlacesFromGlobal(circleId, userId, { includeUserRelations, includePublicContent });
    } else {
      // Use legacy places system
      return await getCirclePlacesFromLegacy(circleId, userId);
    }
  } catch (error) {
    console.error('❌ PlaceTransitionService: Error getting circle places:', error);
    
    // Fallback to legacy system on error
    if (FEATURE_FLAGS.USE_GLOBAL_PLACES_READ) {
      console.log('🔄 Falling back to legacy place system');
      return await getCirclePlacesFromLegacy(circleId, userId);
    }
    
    throw error;
  }
}

// Get places from global system
async function getCirclePlacesFromGlobal(circleId, userId, options = {}) {
  // Get user-place relations for this circle
  const relationsQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
    .where('circleId', '==', circleId)
    .orderBy('addedAt', 'desc')
    .get();
  
  if (relationsQuery.empty) {
    return [];
  }
  
  const relations = serializeQuerySnapshot(relationsQuery);
  const placeIds = relations.map(relation => relation.placeId);
  
  // Get global places (batch processing for large lists)
  const places = [];
  const batchSize = 10; // Firestore 'in' query limit
  
  for (let i = 0; i < placeIds.length; i += batchSize) {
    const batch = placeIds.slice(i, i + batchSize);
    const placesQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .where(admin.firestore.FieldPath.documentId(), 'in', batch)
      .get();
    
    const batchPlaces = serializeQuerySnapshot(placesQuery);
    places.push(...batchPlaces);
  }
  
  // Combine places with their user relations
  const enrichedPlaces = places.map(place => {
    const relation = relations.find(r => r.placeId === place._id);
    
    const enrichedPlace = {
      ...place,
      // Legacy compatibility fields
      id: place._id,
      circleId: circleId,
      addedBy: relation?.userId,
      privacy: relation?.privacy || 'followCircle',
      // New fields
      userRelation: options.includeUserRelations ? relation : undefined,
      isGlobalPlace: true
    };
    
    // Include user-specific notes as legacy 'notes' field for compatibility
    if (relation?.privateNotes) {
      enrichedPlace.notes = relation.privateNotes;
    }
    
    return enrichedPlace;
  });
  
  // Sort by the relation's addedAt time to match legacy behavior
  return enrichedPlaces.sort((a, b) => {
    const relationA = relations.find(r => r.placeId === a._id);
    const relationB = relations.find(r => r.placeId === b._id);
    
    const timeA = new Date(relationA?.addedAt || a.createdAt);
    const timeB = new Date(relationB?.addedAt || b.createdAt);
    
    return timeB - timeA; // Newest first
  });
}

// Get places from legacy system
async function getCirclePlacesFromLegacy(circleId, userId) {
  const placesQuery = await db.collection(COLLECTIONS.PLACES)
    .where('circleId', '==', circleId)
    .orderBy('createdAt', 'desc')
    .get();
  
  return serializeQuerySnapshot(placesQuery);
}

// Add place to circle - supports both legacy and global systems
async function addPlaceToCircle(placeData, circleId, userId, userDisplayName) {
  try {
    if (FEATURE_FLAGS.USE_GLOBAL_PLACES_WRITE) {
      // Use new global places system
      return await addPlaceToCircleGlobal(placeData, circleId, userId, userDisplayName);
    } else if (FEATURE_FLAGS.MIGRATION_MODE) {
      // Write to both systems during migration
      const legacyResult = await addPlaceToCircleLegacy(placeData, circleId, userId);
      
      try {
        await addPlaceToCircleGlobal(placeData, circleId, userId, userDisplayName);
      } catch (error) {
        console.error('❌ Failed to write to global places during migration:', error);
        // Continue with legacy result
      }
      
      return legacyResult;
    } else {
      // Use legacy places system
      return await addPlaceToCircleLegacy(placeData, circleId, userId);
    }
  } catch (error) {
    console.error('❌ PlaceTransitionService: Error adding place to circle:', error);
    throw error;
  }
}

// Add place using global system
async function addPlaceToCircleGlobal(placeData, circleId, userId, userDisplayName) {
  // Check if global place already exists
  let globalPlace = null;
  
  if (placeData.googlePlaceId) {
    const existingQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .where('googlePlaceId', '==', placeData.googlePlaceId)
      .limit(1)
      .get();
    
    if (!existingQuery.empty) {
      globalPlace = serializeDoc(existingQuery.docs[0]);
    }
  }
  
  // Create global place if it doesn't exist
  if (!globalPlace) {
    // Convert legacy photos to attributed format
    const attributedPhotos = [];
    if (placeData.photos && Array.isArray(placeData.photos)) {
      for (const photo of placeData.photos) {
        const photoUrl = typeof photo === 'string' ? photo : photo.url;
        attributedPhotos.push(createAttributedPhoto({
          url: photoUrl,
          uploadedBy: userId,
          uploadedByName: userDisplayName,
          source: photoUrl.includes('googleusercontent.com') ? 'google_places' : 'user_upload'
        }));
      }
    }
    
    // Convert legacy videos to attributed format
    const attributedVideos = [];
    if (placeData.videos && Array.isArray(placeData.videos)) {
      for (const video of placeData.videos) {
        attributedVideos.push(createAttributedVideo({
          videoUrl: typeof video === 'string' ? video : video.videoUrl,
          uploadedBy: userId,
          uploadedByName: userDisplayName,
          title: video.title || '',
          description: video.description || ''
        }));
      }
    }
    
    // Convert notes to public review if present
    const publicReviews = [];
    if (placeData.notes && placeData.notes.trim()) {
      publicReviews.push(createPublicReview({
        userId: userId,
        userName: userDisplayName,
        text: placeData.notes,
        rating: null
      }));
    }
    
    // Create global place
    const globalPlaceData = createGlobalPlace({
      ...placeData,
      photos: attributedPhotos,
      videos: attributedVideos,
      publicReviews: publicReviews
    });
    
    // Set initial statistics
    globalPlaceData.userContributions = {
      totalPhotos: attributedPhotos.length,
      totalVideos: attributedVideos.length,
      totalReviews: publicReviews.length,
      contributors: [userId]
    };
    
    globalPlaceData.totalCircleReferences = 1;
    globalPlaceData.totalUserReferences = 1;
    globalPlaceData.dataCompleteness = calculateDataCompleteness(globalPlaceData);
    globalPlaceData.qualityScore = calculateQualityScore(globalPlaceData);
    
    // Save global place
    const docRef = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).add(globalPlaceData);
    globalPlace = { _id: docRef.id, ...globalPlaceData };
  } else {
    // Update existing global place statistics
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlace._id).update({
      totalCircleReferences: admin.firestore.FieldValue.increment(1),
      'userContributions.contributors': admin.firestore.FieldValue.arrayUnion(userId),
      lastActivityAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Recalculate user references
    const relationsQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
      .where('placeId', '==', globalPlace._id)
      .get();
    
    const uniqueUsers = [...new Set(relationsQuery.docs.map(doc => doc.data().userId))];
    uniqueUsers.push(userId);
    
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlace._id).update({
      totalUserReferences: uniqueUsers.length
    });
  }
  
  // Create user-place relation
  const userPlaceRelation = createUserPlaceRelation({
    userId: userId,
    placeId: globalPlace._id,
    circleId: circleId,
    privateNotes: placeData.privateNotes || null,
    tags: placeData.tags || [],
    privacy: placeData.privacy || 'followCircle'
  });
  
  await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS).add(userPlaceRelation);
  
  // Return in legacy format for API compatibility
  return {
    ...globalPlace,
    id: globalPlace._id,
    circleId: circleId,
    addedBy: userId,
    notes: placeData.privateNotes, // Map private notes to legacy notes field
    privacy: placeData.privacy || 'followCircle',
    isGlobalPlace: true
  };
}

// Add place using legacy system
async function addPlaceToCircleLegacy(placeData, circleId, userId) {
  const { createPlace } = require('../models/FirestoreModels');
  const place = createPlace(placeData, circleId, userId);
  
  const docRef = await db.collection(COLLECTIONS.PLACES).add(place);
  const newPlace = await docRef.get();
  
  return serializeDoc(newPlace);
}

// Update place - handles both systems
async function updatePlace(placeId, updateData, userId) {
  try {
    // Try to find in global places first
    const globalPlaceDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    
    if (globalPlaceDoc.exists && FEATURE_FLAGS.USE_GLOBAL_PLACES_WRITE) {
      return await updateGlobalPlace(placeId, updateData, userId);
    } else {
      return await updateLegacyPlace(placeId, updateData, userId);
    }
  } catch (error) {
    console.error('❌ PlaceTransitionService: Error updating place:', error);
    throw error;
  }
}

async function updateGlobalPlace(placeId, updateData, userId) {
  // For global places, we need to update the place and/or the user relation
  const updates = {};
  const relationUpdates = {};
  
  // Separate global place updates from user-specific updates
  if (updateData.name) updates.name = updateData.name;
  if (updateData.address) updates.address = updateData.address;
  if (updateData.website) updates.website = updateData.website;
  if (updateData.phone) updates.phone = updateData.phone;
  
  // User-specific updates go to the relation
  if (updateData.privateNotes !== undefined) relationUpdates.privateNotes = updateData.privateNotes;
  if (updateData.tags) relationUpdates.tags = updateData.tags;
  if (updateData.privacy) relationUpdates.privacy = updateData.privacy;
  
  // Update global place if needed
  if (Object.keys(updates).length > 0) {
    updates.updatedAt = new Date().toISOString();
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update(updates);
  }
  
  // Update user relation if needed
  if (Object.keys(relationUpdates).length > 0) {
    const relationQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
      .where('userId', '==', userId)
      .where('placeId', '==', placeId)
      .limit(1)
      .get();
    
    if (!relationQuery.empty) {
      relationUpdates.updatedAt = new Date().toISOString();
      await relationQuery.docs[0].ref.update(relationUpdates);
    }
  }
  
  // Return updated place
  const updatedPlaceDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
  return serializeDoc(updatedPlaceDoc);
}

async function updateLegacyPlace(placeId, updateData, userId) {
  const updates = {
    ...updateData,
    updatedAt: new Date().toISOString()
  };
  
  await db.collection(COLLECTIONS.PLACES).doc(placeId).update(updates);
  
  const updatedPlaceDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
  return serializeDoc(updatedPlaceDoc);
}

// Delete place - handles both systems
async function deletePlace(placeId, circleId, userId) {
  try {
    // Check if this is a global place
    const globalPlaceDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    
    if (globalPlaceDoc.exists) {
      return await deleteFromGlobalSystem(placeId, circleId, userId);
    } else {
      return await deleteLegacyPlace(placeId, userId);
    }
  } catch (error) {
    console.error('❌ PlaceTransitionService: Error deleting place:', error);
    throw error;
  }
}

async function deleteFromGlobalSystem(placeId, circleId, userId) {
  // Delete user-place relation
  const relationQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
    .where('userId', '==', userId)
    .where('placeId', '==', placeId)
    .where('circleId', '==', circleId)
    .limit(1)
    .get();
  
  if (!relationQuery.empty) {
    await relationQuery.docs[0].ref.delete();
  }
  
  // Update global place statistics
  await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update({
    totalCircleReferences: admin.firestore.FieldValue.increment(-1),
    updatedAt: new Date().toISOString()
  });
  
  // Check if any relations still exist
  const remainingRelations = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
    .where('placeId', '==', placeId)
    .limit(1)
    .get();
  
  // If no relations remain, consider soft-deleting the global place
  if (remainingRelations.empty) {
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).update({
      deletedAt: new Date().toISOString(),
      totalCircleReferences: 0,
      totalUserReferences: 0
    });
  }
  
  return { success: true, message: 'Place removed from circle' };
}

async function deleteLegacyPlace(placeId, userId) {
  await db.collection(COLLECTIONS.PLACES).doc(placeId).delete();
  return { success: true, message: 'Place deleted' };
}

// Get place by ID - handles both systems
async function getPlaceById(placeId, userId = null) {
  try {
    // Try global places first
    const globalPlaceDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
    
    if (globalPlaceDoc.exists) {
      const place = serializeDoc(globalPlaceDoc);
      
      // Get user relation if userId provided
      if (userId) {
        const relationQuery = await db.collection(GLOBAL_COLLECTIONS.USER_PLACE_RELATIONS)
          .where('userId', '==', userId)
          .where('placeId', '==', placeId)
          .limit(1)
          .get();
        
        if (!relationQuery.empty) {
          const relation = serializeDoc(relationQuery.docs[0]);
          
          // Add legacy compatibility fields
          place.circleId = relation.circleId;
          place.addedBy = relation.userId;
          place.privacy = relation.privacy;
          place.notes = relation.privateNotes; // Map for legacy compatibility
        }
      }
      
      place.id = place._id;
      place.isGlobalPlace = true;
      return place;
    }
    
    // Fallback to legacy system
    const legacyPlaceDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    
    if (legacyPlaceDoc.exists) {
      return serializeDoc(legacyPlaceDoc);
    }
    
    return null;
  } catch (error) {
    console.error('❌ PlaceTransitionService: Error getting place by ID:', error);
    throw error;
  }
}

// Migration helper: Check if a place needs to be migrated
async function checkPlaceMigrationStatus(placeId) {
  const [globalDoc, legacyDoc] = await Promise.all([
    db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get(),
    db.collection(COLLECTIONS.PLACES).doc(placeId).get()
  ]);
  
  return {
    existsInGlobal: globalDoc.exists,
    existsInLegacy: legacyDoc.exists,
    needsMigration: legacyDoc.exists && !globalDoc.exists
  };
}

module.exports = {
  getCirclePlaces,
  addPlaceToCircle,
  updatePlace,
  deletePlace,
  getPlaceById,
  checkPlaceMigrationStatus,
  
  // Internal functions for testing
  getCirclePlacesFromGlobal,
  getCirclePlacesFromLegacy,
  generatePlaceKey,
  
  // Feature flags
  FEATURE_FLAGS
};