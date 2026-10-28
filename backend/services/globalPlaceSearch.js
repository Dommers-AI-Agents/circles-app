// backend/services/globalPlaceSearch.js
//
// Name-word prefix search over the shared venue catalog (globalPlaces).
// Every doc carries `searchTokens` (prefixes of each word in the name), so
// "bak" finds "Test Bakery" and "pizza" finds "Colvitto's Pizza & Bakery".
// Firestore allows one array-contains per query: anchor on the longest token
// and check the rest in memory. Quality-ranked first, then optionally cut to
// a radius and sorted nearest-first.
//
// Shared by the catalog search (GET /places/global/search) and the network
// search (GET /network/places/search) — the latter answers "which of the
// venues matching this text has someone in my network saved?" with one
// indexed read instead of a request per circle (Wes, 2026-10-28).
const geofire = require('geofire-common');
const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { serializeQuerySnapshot } = require('../models/FirestoreModels');

const tokenize = (query) =>
  String(query || '').toLowerCase().split(/[^a-z0-9]+/).filter(Boolean).map(t => t.slice(0, 20));

const coordsOf = (place) => {
  const coords = place.location && place.location.coordinates;
  if (!Array.isArray(coords) || coords.length < 2) return null;
  const [lng, lat] = coords;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  return { lat, lng };
};

/** Great-circle distance in km, or Infinity when the place has no point. */
const distanceKm = (place, lat, lng) => {
  const c = coordsOf(place);
  return c ? geofire.distanceBetween([lat, lng], [c.lat, c.lng]) : Infinity;
};

/**
 * @param {object} opts
 * @param {string} [opts.query]     free text; empty = no text filter
 * @param {string} [opts.category]  exact category, 'all'/empty = any
 * @param {number} [opts.lat] @param {number} [opts.lng]  origin; both present = radius cut + nearest-first
 * @param {number} [opts.radiusKm]  default 50
 * @param {number} opts.limit       quality cut BEFORE the radius filter (ask generously)
 * @param {number} [opts.offset]
 * @returns {Promise<object[]>} serialized venues without the internal search fields
 */
async function searchGlobalPlaces({ query, category, lat, lng, radiusKm = 50, limit, offset = 0 }) {
  const db = getFirestore();
  let placesQuery = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES);

  if (category && category !== 'all') {
    placesQuery = placesQuery.where('category', '==', category);
  }

  const tokens = tokenize(query);
  if (tokens.length > 0) {
    const anchor = tokens.reduce((a, b) => (b.length > a.length ? b : a));
    placesQuery = placesQuery.where('searchTokens', 'array-contains', anchor);
  }

  placesQuery = placesQuery.orderBy('qualityScore', 'desc').limit(limit);
  if (offset > 0) placesQuery = placesQuery.offset(offset);

  let places = serializeQuerySnapshot(await placesQuery.get());

  if (tokens.length > 1) {
    places = places.filter(place => tokens.every(token => (place.searchTokens || []).includes(token)));
  }

  places = places.map(({ searchTokens, nameLower, ...rest }) => rest);

  const hasOrigin = Number.isFinite(lat) && Number.isFinite(lng);
  if (hasOrigin) {
    const maxKm = Number.isFinite(radiusKm) ? radiusKm : 50;
    places = places
      .map(place => ({ place, km: distanceKm(place, lat, lng) }))
      .filter(entry => entry.km <= maxKm)
      .sort((a, b) => a.km - b.km)
      .map(entry => entry.place);
  }

  return places;
}

module.exports = { searchGlobalPlaces, tokenize };
