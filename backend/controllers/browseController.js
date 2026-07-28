// backend/controllers/browseController.js
//
// Network-wide location browse lens over the places a user can see (own + shared
// via getAllowedCircleIds — same visibility model as the map). Circles are never
// modified; location/category are derived views.
//
// Scale strategy (see the scale plan):
//  - TREE (getBrowseLocations): merged from precomputed per-circle summaries and
//    cached per user. Never scans the network on read.
//  - CITY (getBrowseCityPlaces): bounded live query over ONE city, deduped to
//    unique venues, capped. The adaptive people filter falls out of the result.

const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { getFirestore } = require('../config/firebase');
const { getAllowedCircleIds } = require('../utils/networkAccess');
const { getSummaries } = require('../services/circleLocationSummary');
const placeCache = require('../services/placeCache');
const {
  mergeSummaries,
  buildCityVenues,
  densestNeighborhood,
  UNPLACED_KEY
} = require('../services/browseAggregation');

const db = getFirestore();

const TREE_CACHE_TYPE = 'browseTree';
const TREE_TTL_MS = 5 * 60 * 1000;
const CITY_VENUE_CAP = 500;

// GET /api/browse/locations -> { states:[...], unplaced? }  (cached per user)
async function getBrowseLocations(req, res) {
  try {
    const userId = req.user.uid;
    const cached = placeCache.get(TREE_CACHE_TYPE, userId);
    if (cached) return res.status(200).json({ success: true, cached: true, ...cached });

    const { circleIds } = await getAllowedCircleIds(userId);
    const summaries = await getSummaries(circleIds);
    const tree = mergeSummaries(summaries);

    placeCache.set(TREE_CACHE_TYPE, userId, tree, TREE_TTL_MS);
    return res.status(200).json({ success: true, ...tree });
  } catch (error) {
    console.error('❌ [browse] getBrowseLocations failed:', error.message);
    return res.status(500).json({ success: false, message: 'Failed to load location browse' });
  }
}

// Batch-read helpers -------------------------------------------------------

async function fetchCirclePlacesInCity(circleIds, cityKey) {
  const isUnplaced = cityKey === UNPLACED_KEY;
  const chunks = [];
  for (let i = 0; i < circleIds.length; i += 10) chunks.push(circleIds.slice(i, i + 10));

  const snaps = await Promise.all(chunks.map(chunk => {
    let q = db.collection(COLLECTIONS.PLACES).where('circleId', 'in', chunk);
    if (!isUnplaced) q = q.where('cityKey', '==', cityKey);
    return q.get();
  }));

  const seen = new Set();
  const places = [];
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const p = serializeDoc(doc);
      if (p.deletedAt) continue;
      if (isUnplaced && p.stateCode) continue; // in an unplaced-only chunk query, drop placed
      places.push(p);
    }
  }
  return places;
}

async function mapUsers(ids) {
  const map = new Map();
  await Promise.all(ids.map(async id => {
    try {
      const doc = await db.collection(COLLECTIONS.USERS).doc(id).get();
      if (doc.exists) {
        const u = doc.data();
        map.set(id, { id, displayName: u.displayName || 'Someone', profilePicture: u.profilePicture || null });
      }
    } catch (_) { /* best-effort */ }
  }));
  return map;
}

async function mapCircleNames(ids) {
  const map = new Map();
  await Promise.all(ids.map(async id => {
    try {
      const doc = await db.collection(COLLECTIONS.CIRCLES).doc(id).get();
      if (doc.exists) map.set(id, doc.data().name || 'Circle');
    } catch (_) { /* best-effort */ }
  }));
  return map;
}

async function mapVenueRatings(globalPlaceIds) {
  const map = new Map();
  await Promise.all(globalPlaceIds.map(async id => {
    try {
      const doc = await db.collection('globalPlaces').doc(id).get();
      if (doc.exists) {
        const r = doc.data().googleData && doc.data().googleData.rating;
        if (typeof r === 'number') map.set(id, r);
      }
    } catch (_) { /* best-effort */ }
  }));
  return map;
}

// GET /api/browse/cities/:cityKey/places?personId=<uid>
// -> { city, state, stateCode, count, capped, topNeighborhood, people:[...], places:[venue...] }
async function getBrowseCityPlaces(req, res) {
  try {
    const userId = req.user.uid;
    const cityKey = req.params.cityKey;
    const personId = req.query.personId || null; // filter to one saver ('me' => own uid)

    const { circleIds } = await getAllowedCircleIds(userId);
    if (!circleIds.length) {
      return res.status(200).json({ success: true, cityKey, count: 0, places: [], people: [] });
    }

    const allPlaces = await fetchCirclePlacesInCity(circleIds, cityKey);
    const capped = allPlaces.slice(0, CITY_VENUE_CAP);

    const [circleNameById, userById, ratingByVenue] = await Promise.all([
      mapCircleNames([...new Set(capped.map(p => p.circleId).filter(Boolean))]),
      mapUsers([...new Set(capped.map(p => p.addedBy).filter(Boolean))]),
      mapVenueRatings([...new Set(capped.map(p => p.globalPlaceId).filter(Boolean))])
    ]);

    let venues = buildCityVenues(capped, { circleNameById, userById, ratingByVenue, currentUserId: userId });

    // Adaptive people filter: everyone (besides me) who has a place here, with
    // how many venues, computed from the FULL result so it's stable across filters.
    const peopleCounts = new Map();
    venues.forEach(v => v.savers.forEach(s => {
      if (s.id === userId) return;
      const cur = peopleCounts.get(s.id) || { ...s, count: 0 };
      cur.count += 1;
      peopleCounts.set(s.id, cur);
    }));
    const people = [...peopleCounts.values()].sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));

    // Apply the person filter to the venue list (People selector), if any.
    if (personId) {
      const wanted = personId === 'me' ? userId : personId;
      venues = venues.filter(v => v.savers.some(s => s.id === wanted));
    }
    venues.sort((a, b) => a.name.localeCompare(b.name));

    const first = capped[0] || {};
    return res.status(200).json({
      success: true,
      cityKey,
      city: cityKey === UNPLACED_KEY ? 'Unplaced' : (first.city || null),
      state: first.state || null,
      stateCode: first.stateCode || null,
      count: venues.length,
      capped: allPlaces.length > CITY_VENUE_CAP,
      topNeighborhood: densestNeighborhood(venues),
      people,
      places: venues
    });
  } catch (error) {
    console.error('❌ [browse] getBrowseCityPlaces failed:', error.message);
    return res.status(500).json({ success: false, message: 'Failed to load city places' });
  }
}

module.exports = { getBrowseLocations, getBrowseCityPlaces };
