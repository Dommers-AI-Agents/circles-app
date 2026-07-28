// backend/controllers/browseController.js
//
// Location browse lens: aggregate a user's saved places into a State -> City
// tree (with pin counts), and list a city's venues across ALL their circles.
// Reads the denormalized cache fields (stateCode/state/city/cityKey/category/
// neighborhood) that placeLocationDerivation stamps on each save doc.
//
// Counts are per unique VENUE (globalPlaceId), so a venue saved to three circles
// is one pin with three source-circle chips — the "one pin, every lens" idea.
// Circles are never modified; location is a derived view over the same saves.

const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { getFirestore } = require('../config/firebase');
const {
  buildLocationTree,
  buildCityVenues,
  densestNeighborhood,
  UNPLACED_KEY
} = require('../services/browseAggregation');

const db = getFirestore();

// Fetch a user's non-deleted saves. Single-field query (auto-indexed); soft-
// delete filtered in memory to avoid an extra composite index.
async function fetchUserPlaces(userId) {
  const snap = await db.collection(COLLECTIONS.PLACES).where('addedBy', '==', userId).get();
  return snap.docs.map(serializeDoc).filter(p => !p.deletedAt);
}

// GET /api/browse/locations -> { states: [{stateCode, state, count, cities:[...]}], unplaced? }
async function getBrowseLocations(req, res) {
  try {
    const places = await fetchUserPlaces(req.user.uid);
    return res.status(200).json({ success: true, ...buildLocationTree(places) });
  } catch (error) {
    console.error('❌ [browse] getBrowseLocations failed:', error.message);
    return res.status(500).json({ success: false, message: 'Failed to load location browse' });
  }
}

// GET /api/browse/cities/:cityKey/places -> { city, state, stateCode, places:[venue...], topNeighborhood }
async function getBrowseCityPlaces(req, res) {
  try {
    const userId = req.user.uid;
    const cityKey = req.params.cityKey;
    const all = await fetchUserPlaces(userId);

    const inCity = cityKey === UNPLACED_KEY
      ? all.filter(p => !p.stateCode)
      : all.filter(p => p.cityKey === cityKey);

    // Resolve circle names for the chips (only the circles referenced here).
    const circleIds = [...new Set(inCity.map(p => p.circleId).filter(Boolean))];
    const circleNameById = new Map();
    await Promise.all(circleIds.map(async id => {
      try {
        const doc = await db.collection(COLLECTIONS.CIRCLES).doc(id).get();
        if (doc.exists) circleNameById.set(id, doc.data().name || 'Circle');
      } catch (_) { /* best-effort chip label */ }
    }));

    const venues = buildCityVenues(inCity, circleNameById)
      .sort((a, b) => a.name.localeCompare(b.name));

    const first = inCity[0] || {};
    return res.status(200).json({
      success: true,
      cityKey,
      city: cityKey === UNPLACED_KEY ? 'Unplaced' : (first.city || null),
      state: first.state || null,
      stateCode: first.stateCode || null,
      count: venues.length,
      topNeighborhood: densestNeighborhood(venues),
      places: venues
    });
  } catch (error) {
    console.error('❌ [browse] getBrowseCityPlaces failed:', error.message);
    return res.status(500).json({ success: false, message: 'Failed to load city places' });
  }
}

module.exports = { getBrowseLocations, getBrowseCityPlaces };
