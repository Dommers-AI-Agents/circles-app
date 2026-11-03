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
const { sendServiceError } = require('../utils/serviceError');
const { getDocsById } = require('../utils/batchGet');
const { getFirestore } = require('../config/firebase');
const { reachOf, visibleNetworkSaves, circlesFor } = require('../services/placeReach');
const { canSeePlaceCircle } = require('../services/visibility');
const { buildViewerContext } = require('../services/viewerContext');
const placeCache = require('../services/placeCache');
const {
  mergeSummaries,
  summarizeCirclePlaces,
  buildCityVenues,
  densestNeighborhood,
  UNPLACED_KEY,
  COUNTRY_KEY_PREFIX
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

    // From the places themselves (Wes, 2026-11-03: a place's privacy always
    // wins): every network place in reach that this viewer may see, one
    // summary. Per-circle summaries counted private places too, and can't see
    // a public place in a private circle.
    const viewerCtx = await buildViewerContext(userId);
    const reach = await reachOf(userId, viewerCtx);
    const visible = await visibleNetworkSaves(await placesInReach(reach, null, BROWSE_TREE_FIELDS),
      { userId, viewerCtx, reach });
    const tree = mergeSummaries([summarizeCirclePlaces(visible)]);

    placeCache.set(TREE_CACHE_TYPE, userId, tree, TREE_TTL_MS);
    return res.status(200).json({ success: true, ...tree });
  } catch (error) {
    return sendServiceError(res, error, { log: '❌ [browse] getBrowseLocations failed', fallbackMessage: 'Failed to load location browse' });
  }
}

// Batch-read helpers -------------------------------------------------------

// A region key is one of: a city ("charlotte|NC"), a country ("country:CA"), or
// the Unplaced sentinel.
const countryCodeOf = (key) =>
  key.startsWith(COUNTRY_KEY_PREFIX) ? key.slice(COUNTRY_KEY_PREFIX.length) : null;

// What the tree needs from each place: where it is, and the one rule's fields
const BROWSE_TREE_FIELDS = ['cityKey', 'city', 'stateCode', 'state', 'countryCode', 'country', 'deletedAt',
  'addedBy', 'privacy', 'sharedWith', 'audienceListId', 'circleId'];

// The places of everyone in reach (their own saves, plus the circles shared
// with the viewer by name), optionally in one region; `fields` projects.
async function placesInReach(reach, regionKey, fields = null) {
  const isUnplaced = regionKey === UNPLACED_KEY;
  const countryCode = regionKey ? countryCodeOf(regionKey) : null;
  const groups = [];
  for (let i = 0; i < reach.people.length; i += 30) groups.push(['addedBy', reach.people.slice(i, i + 30)]);
  for (let i = 0; i < reach.sharedCircleIds.length; i += 30) groups.push(['circleId', reach.sharedCircleIds.slice(i, i + 30)]);
  const snaps = await Promise.all(groups.map(([field, group]) => {
    let q = db.collection(COLLECTIONS.PLACES).where(field, 'in', group);
    if (regionKey && countryCode) q = q.where('countryCode', '==', countryCode);
    else if (regionKey && !isUnplaced) q = q.where('cityKey', '==', regionKey);
    if (fields) q = q.select(...fields);
    return q.get();
  }));
  const seen = new Set();
  const out = [];
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      out.push(fields ? { id: doc.id, ...doc.data() } : serializeDoc(doc));
    }
  }
  return out;
}

// The places of one region this viewer may see: in reach, by the one rule
// (services/placeReach; a place's privacy wins over its circle's).
async function fetchCirclePlacesInCity(reach, regionKey, { viewerId, viewerCtx } = {}) {
  const isUnplaced = regionKey === UNPLACED_KEY;
  const countryCode = countryCodeOf(regionKey);
  const visible = await visibleNetworkSaves(await placesInReach(reach, regionKey), { userId: viewerId, viewerCtx, reach });

  const places = [];
  {
    for (const p of visible) {
      // In an unplaced-only chunk query, drop anything that IS placed — by US
      // state or by country. Must match summarizeCirclePlaces' precedence.
      if (isUnplaced && (p.stateCode || p.countryCode)) continue;
      // A US place carries countryCode 'US' but belongs to its city, not to a
      // "United States" region row — the tree never emits one.
      if (countryCode && p.stateCode) continue;
      places.push(p);
    }
  }
  return places;
}

// Batched reads (utils/batchGet) — these were one request per id
async function mapUsers(ids) {
  const map = new Map();
  try {
    const docs = await getDocsById(COLLECTIONS.USERS, ids, { fields: ['displayName', 'profilePicture'] });
    for (const [id, doc] of docs) {
      const u = doc.data();
      map.set(id, { id, displayName: u.displayName || 'Someone', profilePicture: u.profilePicture || null });
    }
  } catch (_) { /* best-effort */ }
  return map;
}

async function mapCircleNames(ids) {
  const map = new Map();
  try {
    const docs = await getDocsById(COLLECTIONS.CIRCLES, ids, { fields: ['name'] });
    for (const [id, doc] of docs) map.set(id, doc.data().name || 'Circle');
  } catch (_) { /* best-effort */ }
  return map;
}

async function mapVenueRatings(globalPlaceIds) {
  const map = new Map();
  try {
    const docs = await getDocsById('globalPlaces', globalPlaceIds, { fields: ['googleData.rating'] });
    for (const [id, doc] of docs) {
      const r = doc.data().googleData && doc.data().googleData.rating;
      if (typeof r === 'number') map.set(id, r);
    }
  } catch (_) { /* best-effort */ }
  return map;
}

// GET /api/browse/cities/:cityKey/places?personId=<uid>
// -> { city, state, stateCode, count, capped, topNeighborhood, people:[...], places:[venue...] }
async function getBrowseCityPlaces(req, res) {
  try {
    const userId = req.user.uid;
    const cityKey = req.params.cityKey;
    const personId = req.query.personId || null; // filter to one saver ('me' => own uid)

    const viewerCtx = await buildViewerContext(userId);
    const reach = await reachOf(userId, viewerCtx);
    const allPlaces = await fetchCirclePlacesInCity(reach, cityKey, { viewerId: userId, viewerCtx });
    const capped = allPlaces.slice(0, CITY_VENUE_CAP);

    // A circle's name only where the viewer could open the circle: a public
    // place in a private circle shows without it (Wes, 2026-11-03)
    const circleById = await circlesFor(capped);
    const nameableCircleIds = [...circleById.entries()]
      .filter(([, circle]) => canSeePlaceCircle(circle, userId, viewerCtx)).map(([id]) => id);

    const [circleNameById, userById, ratingByVenue] = await Promise.all([
      mapCircleNames(nameableCircleIds),
      mapUsers([...new Set(capped.map(p => p.addedBy).filter(Boolean))]),
      mapVenueRatings([...new Set(capped.map(p => p.globalPlaceId).filter(Boolean))])
    ]);

    let venues = buildCityVenues(capped, { circleNameById, userById, ratingByVenue, currentUserId: userId, onlyNamedCircles: true });

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
    const countryCode = countryCodeOf(cityKey);
    // A country row has no city; the client shows the country name as the title.
    const title = cityKey === UNPLACED_KEY
      ? 'Unplaced'
      : (countryCode ? (first.country || countryCode) : (first.city || null));
    return res.status(200).json({
      success: true,
      cityKey,
      city: title,
      isCountry: !!countryCode,
      country: first.country || null,
      countryCode: countryCode || first.countryCode || null,
      state: countryCode ? null : (first.state || null),
      stateCode: countryCode ? null : (first.stateCode || null),
      count: venues.length,
      capped: allPlaces.length > CITY_VENUE_CAP,
      topNeighborhood: densestNeighborhood(venues),
      people,
      places: venues
    });
  } catch (error) {
    return sendServiceError(res, error, { log: '❌ [browse] getBrowseCityPlaces failed', fallbackMessage: 'Failed to load city places' });
  }
}

module.exports = { getBrowseLocations, getBrowseCityPlaces };
