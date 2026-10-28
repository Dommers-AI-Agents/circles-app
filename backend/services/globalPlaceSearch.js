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

// The words a person uses for WHAT a place is, mirrored from the app's
// category display names and group titles (ios Models/Place.swift,
// PlaceCategoryGroup.swift) — the home search matches saved places on these
// too, so "coffee" lists the cafés. Keys are folded (accents off, singular).
const CATEGORY_WORDS = {
  restaurant: ['restaurant'], food: ['restaurant'],
  cafe: ['cafe'], coffee: ['cafe'],
  bar: ['bar'], drink: ['bar'],
  hotel: ['hotel'],
  retail: ['retail'], shopping: ['retail'],
  service: ['service'],
  attraction: ['attraction'],
  entertainment: ['entertainment'], fun: ['entertainment'],
  healthcare: ['healthcare'], health: ['healthcare'],
  fitness: ['fitness'],
  education: ['education'], learning: ['education'],
  outdoor: ['outdoor'],
  transport: ['transport'], transit: ['transport'],
  finance: ['finance'],
  home: ['home'], work: ['work'], other: ['other']
};
const singular = (word) => (word.length > 3 && word.endsWith('s') ? word.slice(0, -1) : word);
const fold = (word) => word.normalize('NFD').replace(/[\u0300-\u036f]/g, '');

/**
 * The category ids a query names, when EVERY word of it is a category word
 * ("coffee", "bars", "food"). Mixed queries ("coffee shop") are name searches.
 */
function categoriesNamedBy(query) {
  const words = tokenize(fold(String(query || '')));
  if (words.length === 0) return [];
  const sets = words.map(word => CATEGORY_WORDS[singular(word)] || CATEGORY_WORDS[word]);
  if (sets.some(set => !set)) return [];
  return [...new Set(sets.flat())];
}

/** Catalog venues in the given categories, same radius/sort rules as the text search. */
async function searchGlobalPlacesByCategories({ categories, lat, lng, radiusKm = 50, limit }) {
  const perCategory = await Promise.all(
    categories.map(category => searchGlobalPlaces({ category, lat, lng, radiusKm, limit }))
  );
  return perCategory.flat();
}

/**
 * Text search the way the app's own list matches: by name words AND by what
 * the place is. One sorted, de-duplicated list, nearest first with an origin.
 */
async function searchGlobalPlacesForText({ query, lat, lng, radiusKm = 50, limit }) {
  const categories = categoriesNamedBy(query);
  const [byName, byCategory] = await Promise.all([
    searchGlobalPlaces({ query, lat, lng, radiusKm, limit }),
    categories.length > 0
      ? searchGlobalPlacesByCategories({ categories, lat, lng, radiusKm, limit })
      : Promise.resolve([])
  ]);
  const seen = new Set();
  const merged = [];
  for (const place of [...byName, ...byCategory]) {
    if (seen.has(place.id)) continue;
    seen.add(place.id);
    merged.push(place);
  }
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    merged.sort((a, b) => distanceKm(a, lat, lng) - distanceKm(b, lat, lng));
  }
  return merged;
}

module.exports = { searchGlobalPlaces, searchGlobalPlacesForText, categoriesNamedBy, tokenize };
