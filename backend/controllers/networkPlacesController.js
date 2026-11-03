// backend/controllers/networkPlacesController.js
// Viewport-based place loading: returns places within a geographic radius
// from all circles the requesting user is allowed to see.

const { getFirestore } = require('../config/firebase');
const { sendServiceError } = require('../utils/serviceError');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { reachOf, visibleNetworkSaves } = require('../services/placeReach');
const { isPlaceVisibleToViewer, canSeePlace } = require('../services/visibility');
const { buildViewerContext } = require('../services/viewerContext');
const { normalizeUserId } = require('../services/idService');
const { publicUserSummary } = require('../services/publicProjection');
const { isSameUser } = require('../services/idService');
const { queryInChunks } = require('../utils/firestoreChunks');
const globalPlaceSearch = require('../services/globalPlaceSearch');
const geofire = require('geofire-common');
const { getDocsById } = require('../utils/batchGet');

const db = getFirestore();

// What pass 1 reads to pick the pins: dedupe, deleted, visibility
// (isPlaceVisibleToViewer), the radius check, and the venue link
const VIEWPORT_PICK_FIELDS = ['deletedAt', 'location', 'addedBy', 'privacy', 'sharedWith', 'audienceListId', 'globalPlaceId', 'circleId'];

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
    const syncedAt = new Date();

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

    // Place-first (Wes, 2026-11-03): circles only organize, places carry the
    // location and the privacy that matters. So: the places added by the
    // people whose places this viewer could see (themself, connections,
    // people they follow), inside the map area, each decided by canSeePlace
    // — its own privacy, or its circle's when it follows the circle. Plus the
    // circles someone shared with the viewer by name, whose owner may be
    // outside their network. Was: every visible circle × map patch (174
    // searches for Wes's 288 circles, most of them empty or far away).
    const viewerCtx = await buildViewerContext(userId);
    const reach = await reachOf(userId, viewerCtx, { onlyPerson: connectionId });
    const people = reach.people;
    const sharedCircleIds = reach.sharedCircleIds;

    // Geohash range bounds covering the circle (up to 9 bounds)
    const bounds = geofire.geohashQueryBounds([centerLat, centerLng], radiusM);
    const byPeople = [];
    for (let i = 0; i < people.length; i += 30) byPeople.push(['addedBy', people.slice(i, i + 30)]);
    const byCircles = [];
    for (let i = 0; i < sharedCircleIds.length; i += 30) byCircles.push(['circleId', sharedCircleIds.slice(i, i + 30)]);

    // A cap per (group × patch) query. High enough that the nearest-`limit`
    // pick sees (nearly) everything in view: with ~18 searches instead of 174
    // it's affordable, and a cut in geohash order would drop an arbitrary
    // patch rather than the farthest pins. The client re-queries with a
    // smaller radius on zoom anyway.
    const perQueryLimit = Math.max(limit, 500);
    const queries = [];
    for (const [field, group] of [...byPeople, ...byCircles]) {
      for (const b of bounds) {
        queries.push(
          db.collection(COLLECTIONS.PLACES)
            .where(field, 'in', group)
            .orderBy('geohash')
            .startAt(b[0])
            .endAt(b[1])
            .limit(perQueryLimit)
            // Pass 1 reads only what picks the pins; pass 2 reads the full
            // records of the ones sent
            .select(...VIEWPORT_PICK_FIELDS)
            .get()
        );
      }
    }

    const snapshots = await Promise.all(queries);

    // Post-filter: dedupe across bounds/groups, drop deleted docs, drop
    // geohash false positives outside the precise radius
    const seenIds = new Set();
    const candidates = [];
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
        candidates.push({ doc, data, distanceM });
      }
    }

    // The one rule per pin (its privacy, else its circle's), the circle
    // owner's "not on my map", and network reach (services/placeReach)
    const shown = new Set((await visibleNetworkSaves(candidates.map(c => ({ ...c.data, id: c.doc.id })),
      { userId, viewerCtx, reach, mapOnly: true })).map(save => save.id));
    const matches = candidates.filter(c => shown.has(c.doc.id)).map(({ doc, distanceM }) => ({ doc, distanceM }));

    matches.sort((a, b) => a.distanceM - b.distanceM);
    const hasMore = matches.length > limit;
    const picked = matches.slice(0, limit);

    // "Only what changed" (2026-11-03): the phone sends when it last loaded
    // this same view; Firestore's own update time says which picked pins
    // (or their venues) changed since. Captured before the reads (see
    // places/batch); the margin covers clock skew.
    const sinceMs = Date.parse(req.query.since || '');
    const delta = req.query.lean !== '1' && Number.isFinite(sinceMs);
    const changedAfterMs = sinceMs - 5000;
    let toBuild = picked.map(({ doc }) => doc.ref);
    if (delta) {
      const venueIds = [...new Set(picked.map(({ doc }) => doc.get('globalPlaceId')).filter(Boolean))];
      const venueDocs = venueIds.length
        ? await db.getAll(...venueIds.map(id => db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(id)), { fieldMask: ['commentsCount'] })
        : [];
      const venueUpdatedMs = new Map(venueDocs.filter(d => d.exists).map(d => [d.id, d.updateTime.toMillis()]));
      toBuild = picked.filter(({ doc }) => doc.updateTime.toMillis() > changedAfterMs
          || (venueUpdatedMs.get(doc.get('globalPlaceId')) || 0) > changedAfterMs)
        .map(({ doc }) => doc.ref);
    }

    // Pass 2: the full records, for just the pins being sent
    const fullDocs = toBuild.length ? await db.getAll(...toBuild) : [];
    const fullById = new Map(fullDocs.filter(d => d.exists).map(d => [d.id, d]));
    const places = picked.filter(({ doc }) => fullById.has(doc.id)).map(({ doc }) => {
      const place = serializeDoc(fullById.get(doc.id));
      // privateNotes are only visible to the user who added the place
      if (place.addedBy !== userId) {
        delete place.privateNotes;
      }
      return place;
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

    console.log(`🗺️ Viewport query for ${userId}: center=(${centerLat},${centerLng}) r=${radiusM}m people=${people.length} shared=${sharedCircleIds.length} searches=${queries.length} → ${placesWithSocial.length} places${hasMore ? ' (truncated)' : ''}`);

    if (delta) {
      // The phone merges: `places` are the changed pins in full, `ids` the
      // view as it stands (nearest first; removals implied)
      return res.status(200).json({
        success: true,
        mode: 'delta',
        ids: picked.map(({ doc }) => doc.id),
        places: placesWithSocial,
        syncedAt: syncedAt.toISOString(),
        total: picked.length,
        hasMore,
        clampedRadiusM: radiusM
      });
    }

    res.status(200).json({
      success: true,
      places: placesWithSocial,
      syncedAt: syncedAt.toISOString(),
      total: placesWithSocial.length,
      hasMore,
      clampedRadiusM: radiusM
    });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Error in viewport places query', fallbackMessage: 'Error fetching places in viewport' });
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
    // hide their saves from a text search. Place-first: the saves of these
    // venues by people in reach, each by the one rule (2026-11-03)
    const viewerCtx = await buildViewerContext(userId);
    const reach = await reachOf(userId, viewerCtx);

    const venueRank = new Map(venues.map((venue, index) => [venue.id, index]));
    const saveDocs = await queryInChunks(venues.map(v => v.id), chunk =>
      db.collection(COLLECTIONS.PLACES).where('globalPlaceId', 'in', chunk).get()
    );

    // The viewer's own saves are already on their phone; this is the network
    const others = saveDocs.filter(doc => !isSameUser(doc.data().addedBy, userId));
    const shownIds = new Set((await visibleNetworkSaves(others.map(doc => ({ ...doc.data(), id: doc.id })),
      { userId, viewerCtx, reach })).map(save => save.id));
    const matches = [];
    for (const doc of others) {
      if (!shownIds.has(doc.id)) continue;
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
    sendServiceError(res, error, { log: '❌ Error in network place search', fallbackMessage: 'Error searching network places' });
  }
};

module.exports = { getNetworkPlacesInViewport, searchNetworkPlaces };
