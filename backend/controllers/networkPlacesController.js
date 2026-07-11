// backend/controllers/networkPlacesController.js
// Viewport-based place loading: returns places within a geographic radius
// from all circles the requesting user is allowed to see.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { getAllowedCircleIds } = require('../utils/networkAccess');
const { normalizeUserId } = require('../services/idService');
const geofire = require('geofire-common');

const db = getFirestore();

const MIN_RADIUS_M = 100;
const MAX_RADIUS_M = 100000; // 100 km
const DEFAULT_LIMIT = 200;
const MAX_LIMIT = 500;

// @desc    Get network places within a viewport (center + radius)
// @route   GET /api/network/places/viewport
// @access  Private
const getNetworkPlacesInViewport = async (req, res) => {
  try {
    const userId = req.user.uid;

    const centerLat = parseFloat(req.query.centerLat);
    const centerLng = parseFloat(req.query.centerLng);
    let radiusM = parseFloat(req.query.radiusM);
    let limit = parseInt(req.query.limit, 10);
    const connectionId = req.query.connectionId || null;

    if (!Number.isFinite(centerLat) || centerLat < -90 || centerLat > 90 ||
        !Number.isFinite(centerLng) || centerLng < -180 || centerLng > 180 ||
        !Number.isFinite(radiusM)) {
      return res.status(400).json({
        success: false,
        message: 'centerLat, centerLng and radiusM are required and must be valid numbers'
      });
    }

    radiusM = Math.min(Math.max(radiusM, MIN_RADIUS_M), MAX_RADIUS_M);
    limit = Number.isFinite(limit) ? Math.min(Math.max(limit, 1), MAX_LIMIT) : DEFAULT_LIMIT;

    const { circleIds } = await getAllowedCircleIds(userId, { connectionId });
    if (circleIds.length === 0) {
      return res.status(200).json({
        success: true,
        places: [],
        total: 0,
        hasMore: false,
        clampedRadiusM: radiusM
      });
    }

    // Geohash range bounds covering the circle (up to 9 bounds)
    const bounds = geofire.geohashQueryBounds([centerLat, centerLng], radiusM);

    // Chunk allowed circle IDs by 10 for the 'in' operator
    const circleChunks = [];
    for (let i = 0; i < circleIds.length; i += 10) {
      circleChunks.push(circleIds.slice(i, i + 10));
    }

    const queries = [];
    for (const chunk of circleChunks) {
      for (const b of bounds) {
        queries.push(
          db.collection(COLLECTIONS.PLACES)
            .where('circleId', 'in', chunk)
            .orderBy('geohash')
            .startAt(b[0])
            .endAt(b[1])
            .limit(limit)
            .get()
        );
      }
    }

    const snapshots = await Promise.all(queries);

    // Post-filter: dedupe across bounds/chunks, drop deleted docs, drop
    // geohash false positives outside the precise radius
    const seenIds = new Set();
    const matches = [];

    for (const snapshot of snapshots) {
      for (const doc of snapshot.docs) {
        if (seenIds.has(doc.id)) continue;
        seenIds.add(doc.id);

        const data = doc.data();
        if (data.deletedAt) continue;

        const coords = data.location && data.location.coordinates;
        if (!Array.isArray(coords) || coords.length < 2) continue;
        const [longitude, latitude] = coords;
        if (typeof longitude !== 'number' || typeof latitude !== 'number') continue;

        const distanceM = geofire.distanceBetween([centerLat, centerLng], [latitude, longitude]) * 1000;
        if (distanceM > radiusM) continue;

        const place = serializeDoc(doc);
        // privateNotes are only visible to the user who added the place
        if (place.addedBy !== userId) {
          delete place.privateNotes;
        }
        place._viewportDistanceM = distanceM;
        matches.push(place);
      }
    }

    matches.sort((a, b) => a._viewportDistanceM - b._viewportDistanceM);
    const hasMore = matches.length > limit;
    const places = matches.slice(0, limit).map(place => {
      const { _viewportDistanceM, ...rest } = place;
      return rest;
    });

    // Enrich with the adder's user info (same shape as circles/:id/places) so
    // the app can show "Added by <name>" instead of "Unknown"
    const adderIds = [...new Set(places.map(p => p.addedBy).filter(Boolean))];
    const adderDocs = await Promise.all(
      adderIds.map(id => db.collection(COLLECTIONS.USERS).doc(normalizeUserId(id) || String(id)).get())
    );
    const userMap = new Map();
    adderDocs.forEach((doc, index) => {
      if (doc.exists) {
        const userData = serializeDoc(doc);
        const summary = {
          id: userData.id,
          displayName: userData.displayName || 'Unknown User',
          email: userData.email,
          profilePicture: userData.profilePicture
        };
        userMap.set(userData.id, summary);
        // Also map the original (possibly complex-format) id from the place doc
        if (adderIds[index] !== userData.id) {
          userMap.set(adderIds[index], summary);
        }
      }
    });
    places.forEach(place => {
      place.addedByUser = userMap.get(place.addedBy) || null;
    });

    console.log(`🗺️ Viewport query for ${userId}: center=(${centerLat},${centerLng}) r=${radiusM}m circles=${circleIds.length} → ${places.length} places${hasMore ? ' (truncated)' : ''}`);

    res.status(200).json({
      success: true,
      places,
      total: places.length,
      hasMore,
      clampedRadiusM: radiusM
    });
  } catch (error) {
    console.error('❌ Error in viewport places query:', error);
    res.status(500).json({
      success: false,
      message: 'Error fetching places in viewport',
      error: error.message
    });
  }
};

module.exports = { getNetworkPlacesInViewport };
