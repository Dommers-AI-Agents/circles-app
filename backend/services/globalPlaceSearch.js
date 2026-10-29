// backend/services/globalPlaceSearch.js
//
// Name-word prefix search over the shared venue catalog (globalPlaces).
// Every doc carries `searchTokens` (prefixes of each word in the name), so
// "bak" finds "Test Bakery" and "pizza" finds "Colvitto's Pizza & Bakery".
// Firestore allows one array-contains per query: anchor on the longest token
// and check the rest in memory. With an origin the search is distance-first
// (geohash cells around it, index searchTokens+geohash / category+geohash);
// without one, quality-ranked.
//
// Shared by the catalog search (GET /places/global/search) and the network
// search (GET /network/places/search) — the latter answers "which of the
// venues matching this text has someone in my network saved?" with one
// indexed read instead of a request per circle (Wes, 2026-10-28).
const geofire = require('geofire-common');
const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { serializeQuerySnapshot } = require('../models/FirestoreModels');

const { queryTokens, anchorToken, hasAllTokens, foldText } = require('../utils/searchTokens');

const tokenize = (query) => queryTokens(query);

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

/** Merged-away and deleted venues keep their tokens; search must not show them. */
const isLive = (place) => !place.deletedAt && !place.mergedInto;

const stripInternal = ({ searchTokens, nameLower, geohash, ...rest }) => rest; // eslint-disable-line no-unused-vars

// Reads per geohash cell. A cell holds the venues whose names contain the
// anchor word near the origin — tiny in practice; the cap bounds a dense
// metro with a one-letter query.
const MAX_PER_CELL = 300;

/**
 * Distance-first: "pizza near me" asks each geohash cell around the origin
 * for venues whose name holds the anchor word (index searchTokens+geohash),
 * or that are in the category (index category+geohash). The old path took the
 * platform-wide top-N by quality and only THEN cut to the radius, so as the
 * catalog grew, local results fell out of the window.
 */
async function geoSearch(db, { tokens, category, lat, lng, radiusKm, limit }) {
  const bounds = geofire.geohashQueryBounds([lat, lng], radiusKm * 1000);
  const anchor = tokens.length > 0 ? anchorToken(tokens) : null;
  const perCell = Math.min(Math.max(limit, 1), MAX_PER_CELL);
  const snaps = await Promise.all(bounds.map(([start, end]) => {
    let q = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES);
    q = anchor ? q.where('searchTokens', 'array-contains', anchor) : q.where('category', '==', category);
    return q.orderBy('geohash').startAt(start).endAt(end).limit(perCell).get();
  }));
  const seen = new Set();
  const out = [];
  for (const snap of snaps) {
    for (const place of serializeQuerySnapshot(snap)) {
      if (seen.has(place.id)) continue;
      seen.add(place.id);
      if (!isLive(place)) continue;
      if (tokens.length > 1 && !hasAllTokens(place.searchTokens, tokens)) continue;
      if (anchor && category && category !== 'all' && place.category !== category) continue;
      const km = distanceKm(place, lat, lng);
      if (km > radiusKm) continue;
      out.push({ place, km });
    }
  }
  // Nearest first; equal distances (same building) by quality
  out.sort((a, b) => (a.km - b.km) || ((b.place.qualityScore || 0) - (a.place.qualityScore || 0)));
  return out.map(entry => entry.place);
}

/** Quality-ranked token/category query — no origin, or nothing nearby. */
async function qualitySearch(db, { tokens, category, limit, offset }) {
  let q = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES);
  if (category && category !== 'all') q = q.where('category', '==', category);
  if (tokens.length > 0) q = q.where('searchTokens', 'array-contains', anchorToken(tokens));
  q = q.orderBy('qualityScore', 'desc').limit(limit);
  if (offset > 0) q = q.offset(offset);
  let places = serializeQuerySnapshot(await q.get()).filter(isLive);
  if (tokens.length > 1) places = places.filter(place => hasAllTokens(place.searchTokens, tokens));
  return places;
}

/**
 * @param {object} opts
 * @param {string} [opts.query]     free text; empty = no text filter
 * @param {string} [opts.category]  exact category, 'all'/empty = any
 * @param {number} [opts.lat] @param {number} [opts.lng]  origin; both present = radius cut + nearest-first
 * @param {number} [opts.radiusKm]  default 50
 * @param {number} opts.limit       max venues to consider (per geohash cell with an origin)
 * @param {number} [opts.offset]
 * @param {object} [opts.db]        injectable for tests
 * @returns {Promise<object[]>} serialized venues without the internal search fields
 */
async function searchGlobalPlaces({ query, category, lat, lng, radiusKm = 50, limit, offset = 0, db = getFirestore() }) {
  const tokens = tokenize(query);
  const hasOrigin = Number.isFinite(lat) && Number.isFinite(lng);
  const maxKm = Number.isFinite(radiusKm) ? radiusKm : 50;
  const hasCategory = Boolean(category && category !== 'all');

  if (hasOrigin && (tokens.length > 0 || hasCategory)) {
    const near = await geoSearch(db, { tokens, category, lat, lng, radiusKm: maxKm, limit });
    if (near.length > 0) {
      return near.slice(offset, offset + limit).map(stripInternal);
    }
    // Nothing with a geohash nearby (a venue not yet stamped): the old path
  }

  let places = await qualitySearch(db, { tokens, category, limit, offset });
  places = places.map(stripInternal);
  if (hasOrigin) {
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

/**
 * The category ids a query names, when EVERY word of it is a category word
 * ("coffee", "bars", "food"). Mixed queries ("coffee shop") are name searches.
 */
function categoriesNamedBy(query) {
  const words = tokenize(foldText(String(query || '')));
  if (words.length === 0) return [];
  const sets = words.map(word => CATEGORY_WORDS[singular(word)] || CATEGORY_WORDS[word]);
  if (sets.some(set => !set)) return [];
  return [...new Set(sets.flat())];
}

/** Catalog venues in the given categories, same radius/sort rules as the text search. */
async function searchGlobalPlacesByCategories({ categories, lat, lng, radiusKm = 50, limit, db }) {
  const perCategory = await Promise.all(
    categories.map(category => searchGlobalPlaces({ category, lat, lng, radiusKm, limit, db }))
  );
  return perCategory.flat();
}

/**
 * Text search the way the app's own list matches: by name words AND by what
 * the place is. One sorted, de-duplicated list, nearest first with an origin.
 */
async function searchGlobalPlacesForText({ query, lat, lng, radiusKm = 50, limit, db }) {
  const categories = categoriesNamedBy(query);
  const [byName, byCategory] = await Promise.all([
    searchGlobalPlaces({ query, lat, lng, radiusKm, limit, db }),
    categories.length > 0
      ? searchGlobalPlacesByCategories({ categories, lat, lng, radiusKm, limit, db })
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
