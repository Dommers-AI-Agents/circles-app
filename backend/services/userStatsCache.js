// Cached per-user place/circle totals.
//
// Ranking people ("who has saved the most places", "is this profile worth
// following") needs counts for many users at once, which is the one shape a
// per-row lookup cannot serve. The counts already live denormalized on circle
// docs, so this rolls them up owner-by-owner in a single collection read and
// holds the result briefly.
//
// The read this replaces was happening on *every* discovery request, so a user
// flipping between tabs re-read the entire circles collection each time. Counts
// being a few minutes stale is invisible in a list of suggestions; the repeated
// full scan was not.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const placeCache = require('./placeCache');

const db = getFirestore();

const CACHE_TYPE = 'userPlaceCounts';
const CACHE_KEY = 'all';
// 15 min: the map is derived from a FULL circles-collection scan, so a longer
// TTL matters more than perfectly current circle counts on people cards.
const TTL_MS = 15 * 60 * 1000;

/**
 * ownerId -> { placesCount, circlesCount } for every user who owns a circle.
 * Users with no circles are simply absent; callers should default to zeroes.
 */
const getPlaceCountMap = async () => {
  const cached = placeCache.get(CACHE_TYPE, CACHE_KEY);
  if (cached) return cached;

  const snap = await db.collection(COLLECTIONS.CIRCLES).get();
  const map = new Map();

  snap.docs.forEach((doc) => {
    const circle = doc.data();
    if (!circle.owner) return;
    const current = map.get(circle.owner) || { placesCount: 0, circlesCount: 0 };
    current.placesCount += (circle.placesCount || 0);
    current.circlesCount += 1;
    map.set(circle.owner, current);
  });

  placeCache.set(CACHE_TYPE, CACHE_KEY, map, TTL_MS);
  return map;
};

/** Counts for a single user, defaulted so callers never branch on undefined. */
const getCountsFor = async (userId) => {
  const map = await getPlaceCountMap();
  return map.get(userId) || { placesCount: 0, circlesCount: 0 };
};

/**
 * Drop the cache. Worth calling after a bulk import or migration, where waiting
 * out the TTL would show visibly wrong numbers.
 */
const invalidate = () => placeCache.clear(CACHE_TYPE, CACHE_KEY);

module.exports = { getPlaceCountMap, getCountsFor, invalidate };
