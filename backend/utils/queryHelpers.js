// Query Helper Functions
// Utility functions to handle common Firestore query patterns correctly

/**
 * IMPORTANT: Firestore Query Bug Documentation
 * 
 * ❌ NEVER USE: .where('deletedAt', '==', null)
 * 
 * This query does NOT match documents where deletedAt is undefined!
 * In Firestore: undefined ≠ null
 * 
 * Places created without deletion have deletedAt: undefined
 * Only places that were restored have deletedAt: null
 * 
 * ✅ CORRECT APPROACH: Get all documents then filter in JavaScript
 */

/**
 * Filter places to get only active (non-deleted) ones
 * Handles both undefined and null deletedAt values correctly
 * 
 * @param {Array} placeDocs - Array of Firestore document snapshots
 * @returns {Array} Array of active place documents
 */
function filterActivePlaces(placeDocs) {
  return placeDocs.filter(doc => {
    const place = doc.data();
    // A place is active if deletedAt is falsy (undefined, null, or empty)
    return !place.deletedAt || place.deletedAt === null;
  });
}

/**
 * Check if a single place is active (non-deleted)
 * 
 * @param {Object} placeData - The place data object
 * @returns {boolean} True if place is active, false if deleted
 */
function isPlaceActive(placeData) {
  return !placeData.deletedAt || placeData.deletedAt === null;
}

/**
 * Get active places count from a Firestore collection
 * Use this instead of buggy .where('deletedAt', '==', null) queries
 * 
 * @param {FirebaseFirestore.CollectionReference} db - Firestore instance
 * @param {string} collectionName - Name of collection to query
 * @param {string} circleId - Circle ID to filter by
 * @returns {Promise<number>} Count of active places
 */
async function getActivePlacesCount(db, collectionName, circleId) {
  const allPlacesSnapshot = await db.collection(collectionName)
    .where('circleId', '==', circleId)
    .get();
  
  const activePlaces = filterActivePlaces(allPlacesSnapshot.docs);
  return activePlaces.length;
}

/**
 * Get active places documents from a Firestore collection
 * 
 * @param {FirebaseFirestore.CollectionReference} db - Firestore instance
 * @param {string} collectionName - Name of collection to query
 * @param {string} circleId - Circle ID to filter by
 * @returns {Promise<Array>} Array of active place documents
 */
async function getActivePlaces(db, collectionName, circleId) {
  const allPlacesSnapshot = await db.collection(collectionName)
    .where('circleId', '==', circleId)
    .get();
  
  return filterActivePlaces(allPlacesSnapshot.docs);
}

/**
 * Count places by deletion status for debugging
 * 
 * @param {Array} placeDocs - Array of place document snapshots
 * @returns {Object} Counts of active, deleted, undefined, and null places
 */
function analyzePlaceDeletionStatus(placeDocs) {
  const stats = {
    total: placeDocs.length,
    active: 0,
    deleted: 0,
    undefined: 0,
    null: 0
  };
  
  placeDocs.forEach(doc => {
    const place = doc.data();
    const deletedAt = place.deletedAt;
    
    if (!deletedAt) {
      if (deletedAt === undefined) {
        stats.undefined++;
      } else if (deletedAt === null) {
        stats.null++;
      }
      stats.active++;
    } else {
      stats.deleted++;
    }
  });
  
  return stats;
}

module.exports = {
  filterActivePlaces,
  isPlaceActive,
  getActivePlacesCount,
  getActivePlaces,
  analyzePlaceDeletionStatus
};