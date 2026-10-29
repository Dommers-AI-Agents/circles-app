const { getFirestore, FieldValue, GeoPoint } = require('../config/firebase');
const { sendServiceError } = require('../utils/serviceError');
const { 
  COLLECTIONS, 
  createPlaceVisit, 
  validatePlaceVisit,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { clampPagination } = require('../utils/pagination');
// Activity logging removed - not needed for visit tracking

const db = getFirestore();

// Track a new visit
exports.trackVisit = async (req, res) => {
  try {
    const userId = req.user.uid;
    const visitData = req.body;

    // Create visit record
    const visit = createPlaceVisit(visitData, userId);
    
    // If location coordinates are provided, convert to GeoPoint
    if (visitData.latitude && visitData.longitude) {
      visit.location = new GeoPoint(visitData.latitude, visitData.longitude);
    }

    // Validate the visit data
    const errors = validatePlaceVisit(visit);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }

    // Save to Firestore
    const visitRef = await db.collection(COLLECTIONS.PLACE_VISITS).add(visit);
    const visitDoc = await visitRef.get();

    // Activity logging can be added later if needed
    // For now, just save the visit

    res.status(201).json({
      success: true,
      data: serializeDoc(visitDoc)
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error tracking visit', fallbackMessage: 'Failed to track visit' });
  }
};

// Get user's visit history
exports.getVisits = async (req, res) => {
  try {
    const userId = req.user.uid;
    // Capped (security audit 2026-10-01). Visits are the caller's own rows,
    // and Settings → Export asks for limit=1000, so the cap is higher here.
    const { limit, offset } = clampPagination(req.query, { defaultLimit: 50, maxLimit: 1000, maxOffset: 10000 });
    const {
      reviewed,
      dismissed,
      startDate,
      endDate
    } = req.query;

    let query = db.collection(COLLECTIONS.PLACE_VISITS)
      .where('userId', '==', userId)
      .orderBy('visitedAt', 'desc');

    // Apply filters
    if (reviewed !== undefined) {
      query = query.where('reviewed', '==', reviewed === 'true');
    }

    if (dismissed !== undefined) {
      query = query.where('dismissed', '==', dismissed === 'true');
    }

    if (startDate) {
      query = query.where('visitedAt', '>=', startDate);
    }

    if (endDate) {
      query = query.where('visitedAt', '<=', endDate);
    }

    // Apply pagination
    query = query.limit(limit).offset(offset);

    const snapshot = await query.get();
    let visits = serializeQuerySnapshot(snapshot);
    
    // Deduplicate consecutive visits to the same location
    const deduplicatedVisits = [];
    let lastLocation = null;
    
    for (const visit of visits) {
      // Check if this visit is at the same location as the previous one
      const currentLocation = {
        lat: visit.location?.latitude || 0,
        lng: visit.location?.longitude || 0,
        name: visit.placeName
      };
      
      const isSameLocation = lastLocation && 
        Math.abs(currentLocation.lat - lastLocation.lat) < 0.0001 && // ~11 meters
        Math.abs(currentLocation.lng - lastLocation.lng) < 0.0001 &&
        currentLocation.name === lastLocation.name;
      
      if (!isSameLocation) {
        deduplicatedVisits.push(visit);
        lastLocation = currentLocation;
      } else {
        // If same location, update the duration of the previous visit
        const lastVisit = deduplicatedVisits[deduplicatedVisits.length - 1];
        if (lastVisit && visit.duration) {
          lastVisit.duration = (lastVisit.duration || 0) + visit.duration;
          // Update the end time to reflect the extended visit
          lastVisit.extendedVisit = true;
          lastVisit.consolidatedCount = (lastVisit.consolidatedCount || 1) + 1;
        }
      }
    }
    
    visits = deduplicatedVisits;

    // Get total count for pagination
    const countQuery = db.collection(COLLECTIONS.PLACE_VISITS)
      .where('userId', '==', userId);
    const countSnapshot = await countQuery.count().get();
    const totalCount = countSnapshot.data().count;

    res.json({
      success: true,
      data: visits,
      pagination: {
        total: totalCount,
        limit,
        offset,
        hasMore: offset + visits.length < totalCount
      }
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error getting visits', fallbackMessage: 'Failed to get visits' });
  }
};

// Bulk add visits to circles
exports.bulkAddToCircles = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { visitIds, circleIds } = req.body;

    if (!visitIds || !Array.isArray(visitIds) || visitIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Visit IDs are required'
      });
    }

    if (!circleIds || !Array.isArray(circleIds) || circleIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Circle IDs are required'
      });
    }

    const batch = db.batch();
    const results = {
      added: [],
      failed: []
    };

    // Process each visit
    for (const visitId of visitIds) {
      try {
        const visitRef = db.collection(COLLECTIONS.PLACE_VISITS).doc(visitId);
        const visitDoc = await visitRef.get();

        if (!visitDoc.exists || visitDoc.data().userId !== userId) {
          results.failed.push({ visitId, reason: 'Visit not found or unauthorized' });
          continue;
        }

        const visitData = visitDoc.data();

        // Update visit to mark as reviewed and add circle references
        batch.update(visitRef, {
          reviewed: true,
          addedToCircles: FieldValue.arrayUnion(...circleIds),
          updatedAt: new Date().toISOString()
        });

        // Add places to circles
        for (const circleId of circleIds) {
          const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
          const circleDoc = await circleRef.get();

          if (!circleDoc.exists || circleDoc.data().owner !== userId) {
            results.failed.push({ visitId, circleId, reason: 'Circle not found or unauthorized' });
            continue;
          }

          // Create place from visit data
          const placeData = {
            name: visitData.placeName,
            address: visitData.placeAddress,
            location: visitData.location,
            category: visitData.category,
            notes: visitData.notes,
            photos: visitData.photos,
            ...visitData.placeData,
            addedBy: userId,
            addedAt: new Date().toISOString(),
            fromVisit: visitId
          };

          // Add place to circle's places subcollection
          const placeRef = await db.collection(COLLECTIONS.CIRCLES)
            .doc(circleId)
            .collection('places')
            .add(placeData);

          results.added.push({
            visitId,
            circleId,
            placeId: placeRef.id
          });
        }
      } catch (error) {
        results.failed.push({ visitId, reason: error.message });
      }
    }

    // Commit the batch
    await batch.commit();

    res.json({
      success: true,
      results
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error bulk adding visits', fallbackMessage: 'Failed to add visits to circles' });
  }
};

// Update visit (mark as reviewed, dismissed, etc.)
exports.updateVisit = async (req, res) => {
  try {
    const userId = req.user.uid;
    const visitId = req.params.visitId;
    const updates = req.body;

    const visitRef = db.collection(COLLECTIONS.PLACE_VISITS).doc(visitId);
    const visitDoc = await visitRef.get();

    if (!visitDoc.exists || visitDoc.data().userId !== userId) {
      return res.status(404).json({
        success: false,
        message: 'Visit not found'
      });
    }

    // Only allow certain fields to be updated
    const allowedUpdates = ['reviewed', 'dismissed', 'notes', 'photos'];
    const filteredUpdates = {};
    
    for (const key of allowedUpdates) {
      if (updates[key] !== undefined) {
        filteredUpdates[key] = updates[key];
      }
    }
    // "Which place were you at?": the visit takes the business the person
    // picked (or the app suggested) instead of a bare street address
    const { clean } = require('../utils/text');
    const placeName = clean(updates.placeName, 120);
    if (placeName) filteredUpdates.placeName = placeName;
    const placeAddress = clean(updates.placeAddress, 200);
    if (placeAddress) filteredUpdates.placeAddress = placeAddress;
    if (updates.category !== undefined) filteredUpdates.category = clean(updates.category, 60) || null;

    filteredUpdates.updatedAt = new Date().toISOString();

    await visitRef.update(filteredUpdates);
    const updatedDoc = await visitRef.get();

    res.json({
      success: true,
      data: serializeDoc(updatedDoc)
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error updating visit', fallbackMessage: 'Failed to update visit' });
  }
};

// Delete a visit
exports.deleteVisit = async (req, res) => {
  try {
    const userId = req.user.uid;
    const visitId = req.params.visitId;

    const visitRef = db.collection(COLLECTIONS.PLACE_VISITS).doc(visitId);
    const visitDoc = await visitRef.get();

    if (!visitDoc.exists || visitDoc.data().userId !== userId) {
      return res.status(404).json({
        success: false,
        message: 'Visit not found'
      });
    }

    await visitRef.delete();

    res.json({
      success: true,
      message: 'Visit deleted successfully'
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error deleting visit', fallbackMessage: 'Failed to delete visit' });
  }
};

// Update visit tracking preferences
exports.updateTrackingPreferences = async (req, res) => {
  try {
    const userId = req.user.uid;
    const preferences = req.body;

    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    
    await userRef.update({
      'preferences.visitTracking': preferences,
      updatedAt: new Date().toISOString()
    });

    res.json({
      success: true,
      message: 'Visit tracking preferences updated',
      data: preferences
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error updating tracking preferences', fallbackMessage: 'Failed to update tracking preferences' });
  }
};

// Clear all visits for a user
exports.clearAllVisits = async (req, res) => {
  try {
    const userId = req.user.uid;
    
    // Get all visits for the user
    const visitsSnapshot = await db.collection(COLLECTIONS.PLACE_VISITS)
      .where('userId', '==', userId)
      .get();
    
    // Delete in batches
    const batch = db.batch();
    let deleteCount = 0;
    
    visitsSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
      deleteCount++;
    });
    
    if (deleteCount > 0) {
      await batch.commit();
    }
    
    res.json({
      success: true,
      message: `Cleared ${deleteCount} visits`,
      count: deleteCount
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error clearing visits', fallbackMessage: 'Failed to clear visits' });
  }
};

// Get visit statistics
exports.getVisitStats = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all visits for the user
    const visitsSnapshot = await db.collection(COLLECTIONS.PLACE_VISITS)
      .where('userId', '==', userId)
      .get();

    const visits = serializeQuerySnapshot(visitsSnapshot);
    
    // Calculate statistics
    const stats = {
      totalVisits: visits.length,
      reviewedVisits: visits.filter(v => v.reviewed).length,
      unreviewedVisits: visits.filter(v => !v.reviewed && !v.dismissed).length,
      dismissedVisits: visits.filter(v => v.dismissed).length,
      totalDuration: visits.reduce((sum, v) => sum + (v.duration || 0), 0),
      visitsByCategory: {},
      visitsByMonth: {},
      topVisitedPlaces: []
    };

    // Group by category
    visits.forEach(visit => {
      const category = visit.category || 'Unknown';
      stats.visitsByCategory[category] = (stats.visitsByCategory[category] || 0) + 1;
    });

    // Group by month
    visits.forEach(visit => {
      const date = new Date(visit.visitedAt);
      const monthKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      stats.visitsByMonth[monthKey] = (stats.visitsByMonth[monthKey] || 0) + 1;
    });

    // Find top visited places
    const placeVisitCounts = {};
    visits.forEach(visit => {
      const key = visit.placeName;
      if (!placeVisitCounts[key]) {
        placeVisitCounts[key] = {
          placeName: visit.placeName,
          placeAddress: visit.placeAddress,
          count: 0,
          totalDuration: 0
        };
      }
      placeVisitCounts[key].count++;
      placeVisitCounts[key].totalDuration += visit.duration || 0;
    });

    stats.topVisitedPlaces = Object.values(placeVisitCounts)
      .sort((a, b) => b.count - a.count)
      .slice(0, 10);

    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error getting visit stats', fallbackMessage: 'Failed to get visit statistics' });
  }
};

// Update exclusion settings
exports.updateExclusionSettings = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { excludeHome, excludeWork, homeAddress, workAddress } = req.body;
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    
    await userRef.update({
      'preferences.visitExclusions': {
        excludeHome,
        excludeWork,
        homeAddress,
        workAddress,
        updatedAt: new Date().toISOString()
      },
      updatedAt: new Date().toISOString()
    });
    
    res.json({
      success: true,
      message: 'Exclusion settings updated',
      data: {
        excludeHome,
        excludeWork,
        homeAddress,
        workAddress
      }
    });
  } catch (error) {
    sendServiceError(res, error, { log: 'Error updating exclusion settings', fallbackMessage: 'Failed to update exclusion settings' });
  }
};