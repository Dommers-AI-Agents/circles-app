// backend/controllers/networkPlacesController.js
// Viewport-based place loading: returns places within a geographic radius
// from all circles the requesting user is allowed to see.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { getAllowedCircleIds } = require('../utils/networkAccess');
const { isPlaceVisibleToViewer } = require('../services/visibility');
const { buildViewerContext } = require('../services/viewerContext');
const { normalizeUserId } = require('../services/idService');
const { publicUserSummary } = require('../services/publicProjection');
const { isSameUser } = require('../services/idService');
const { queryInChunks } = require('../utils/firestoreChunks');
const globalPlaceSearch = require('../services/globalPlaceSearch');
const geofire = require('geofire-common');
const { getDocsById } = require('../utils/batchGet');

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

    // mapOnly: honors each circle owner's showOnMap opt-out (map clutter
    // control for bulk-import circles) — list/browse endpoints are unaffected
    const [{ circleIds }, viewerCtx] = await Promise.all([
      getAllowedCircleIds(userId, { connectionId, mapOnly: true }),
      buildViewerContext(userId)
    ]);
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

    // Each (chunk × bound) query previously carried the full response limit
    // (200), so a dense viewport could read up to chunks × bounds × 200 docs
    // to return 200. Cap per-query reads instead; the client re-queries with
    // a smaller radius on zoom, so dense areas fill in as the user zooms.
    const perQueryLimit = Math.min(limit, 60);
    const queries = [];
    for (const chunk of circleChunks) {
      for (const b of bounds) {
        queries.push(
          db.collection(COLLECTIONS.PLACES)
            .where('circleId', 'in', chunk)
            .orderBy('geohash')
            .startAt(b[0])
            .endAt(b[1])
            .limit(perQueryLimit)
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
        // The place's own privacy narrows its circle's: Private is owner-only
        // and Inner Circle reaches only the owner's list, even inside a circle
        // the viewer can otherwise see.
        if (!isPlaceVisibleToViewer(data, userId, viewerCtx)) continue;

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

    // Lean pin mode (opt-in via ?lean=1): map markers draw only name/
    // coordinates/category, so skip the adder + venue/social enrichment and
    // return just what a pin needs. The DEFAULT response keeps the full shape
    // — the shipped client renders these places in list/card surfaces too.
    if (req.query.lean === '1') {
      return res.status(200).json({
        success: true,
        places: places.map(p => ({
          id: p.id,
          name: p.name,
          address: p.address,
          location: p.location,
          circleId: p.circleId,
          category: p.category,
          customCategoryId: p.customCategoryId,
          globalPlaceId: p.globalPlaceId,
          addedBy: p.addedBy
        })),
        total: places.length,
        hasMore,
        clampedRadiusM: radiusM,
        lean: true
      });
    }

    const placesWithSocial = await enrichNetworkPlaces(places);

    console.log(`🗺️ Viewport query for ${userId}: center=(${centerLat},${centerLng}) r=${radiusM}m circles=${circleIds.length} → ${placesWithSocial.length} places${hasMore ? ' (truncated)' : ''}`);

    res.status(200).json({
      success: true,
      places: placesWithSocial,
      total: placesWithSocial.length,
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

// Enrich save records the way every network list expects them: the adder's
// public summary ("Added by <name>") and the venue's social/venue overlay so
// cards match the detail page. Shared by the viewport and the search.
async function enrichNetworkPlaces(places) {
  const adderIds = [...new Set(places.map(p => p.addedBy).filter(Boolean))];
  const docIdOf = (id) => normalizeUserId(id) || String(id);
  // One batched read (was a request per adder)
  const byId = await getDocsById(COLLECTIONS.USERS, adderIds.map(docIdOf),
    { fields: ['displayName', 'profilePicture'] });
  const adderDocs = adderIds.map(id => byId.get(docIdOf(id)) || { exists: false });
  const userMap = new Map();
  adderDocs.forEach((doc, index) => {
    if (doc.exists) {
      const userData = serializeDoc(doc);
      // Name and photo only — never another user's email (security audit
      // 2026-10-01).
      const summary = publicUserSummary(userData);
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

  // Required lazily: placeReadService and this controller's dependency chain
  // meet at module load time.
  const { fetchGlobalSocialMap, overlayVenueFields } = require('../services/placeReadService');
  const socialByGlobalId = await fetchGlobalSocialMap(places);
  return places.map(place => {
    const social = socialByGlobalId.get(place.globalPlaceId);
    if (!social) return place;
    return {
      ...overlayVenueFields(place, social.venueData),
      likes: social.likes,
      likesCount: social.likes.length,
      commentsCount: social.commentsCount
    };
  });
}

const SEARCH_DEFAULT_RADIUS_KM = 80;
const SEARCH_MAX_RADIUS_KM = 200;
// Quality cut per channel BEFORE the radius filter. The catalog holds ~1.6k
// venues and the busiest name word matches under 100 (2026-10-28), so 300
// is headroom, not a ceiling anyone hits.
const SEARCH_VENUE_LIMIT = 300;
const SEARCH_DEFAULT_LIMIT = 50;
const SEARCH_MAX_LIMIT = 100;

// @desc    Places saved by people in my network whose venue matches the text —
//          by name words, or by what it is ("coffee" lists their cafés, as the
//          app's own list does) — the home search's second source. Indexed
//          catalog reads plus one chunked lookup of their saves, instead of
//          the client fetching every network circle's places (239 requests
//          for a large network; the search waited on the last one).
// @route   GET /api/network/places/search?query=&lat=&lng=&radiusKm=&limit=
// @access  Private
const searchNetworkPlaces = async (req, res) => {
  try {
    const userId = req.user.uid;
    const query = String(req.query.query || '').trim();
    if (!query) {
      return res.status(400).json({ success: false, message: 'query is required' });
    }
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const hasOrigin = Number.isFinite(lat) && Number.isFinite(lng)
      && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
    let radiusKm = parseFloat(req.query.radiusKm);
    radiusKm = Number.isFinite(radiusKm)
      ? Math.min(Math.max(radiusKm, 1), SEARCH_MAX_RADIUS_KM)
      : SEARCH_DEFAULT_RADIUS_KM;
    let limit = parseInt(req.query.limit, 10);
    limit = Number.isFinite(limit) ? Math.min(Math.max(limit, 1), SEARCH_MAX_LIMIT) : SEARCH_DEFAULT_LIMIT;

    const venues = await globalPlaceSearch.searchGlobalPlacesForText({
      query,
      lat: hasOrigin ? lat : undefined,
      lng: hasOrigin ? lng : undefined,
      radiusKm,
      limit: SEARCH_VENUE_LIMIT
    });
    if (venues.length === 0) {
      return res.status(200).json({ success: true, places: [], total: 0, hasMore: false });
    }

    // List surface, not the map: a circle owner's showOnMap opt-out does not
    // hide their saves from a text search.
    const [{ circleIds }, viewerCtx] = await Promise.all([
      getAllowedCircleIds(userId),
      buildViewerContext(userId)
    ]);
    const allowedCircles = new Set(circleIds);
    if (allowedCircles.size === 0) {
      return res.status(200).json({ success: true, places: [], total: 0, hasMore: false });
    }

    const venueRank = new Map(venues.map((venue, index) => [venue.id, index]));
    const saveDocs = await queryInChunks(venues.map(v => v.id), chunk =>
      db.collection(COLLECTIONS.PLACES).where('globalPlaceId', 'in', chunk).get()
    );

    const matches = [];
    for (const doc of saveDocs) {
      const data = doc.data();
      if (data.deletedAt) continue;
      // The viewer's own saves are already on their phone; this is the network
      if (isSameUser(data.addedBy, userId)) continue;
      if (!allowedCircles.has(data.circleId)) continue;
      if (!isPlaceVisibleToViewer(data, userId, viewerCtx)) continue;
      const place = serializeDoc(doc);
      delete place.privateNotes;
      matches.push(place);
    }
    // Nearest venue first (the catalog already sorted by distance when an
    // origin was given, by quality otherwise); several saves of one venue
    // stay together.
    matches.sort((a, b) => (venueRank.get(a.globalPlaceId) ?? Infinity) - (venueRank.get(b.globalPlaceId) ?? Infinity));
    const hasMore = matches.length > limit;
    const places = await enrichNetworkPlaces(matches.slice(0, limit));

    res.status(200).json({ success: true, places, total: places.length, hasMore });
  } catch (error) {
    console.error('❌ Error in network place search:', error);
    res.status(500).json({ success: false, message: 'Error searching network places', error: error.message });
  }
};

module.exports = { getNetworkPlacesInViewport, searchNetworkPlaces };
