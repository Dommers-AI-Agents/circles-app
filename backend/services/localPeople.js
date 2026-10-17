// Who saves places near someone, for "People you may know" (Wes, 2026-10-17:
// a new Charlotte user should see Charlotte people first). Where the viewer
// is: their GPS, else where their saves are, else Charlotte
// (config/defaultLocation.js).
const geofire = require('geofire-common');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { DEFAULT_LOCATION } = require('../config/defaultLocation');
const { effectiveCoords } = require('./userCardEnrichment');

const db = getFirestore();
const RADIUS_M = 80 * 1000;
const PER_QUERY = 200;
// Saves narrowed to an Inner Circle or Private don't say where someone is
const HIDDEN_TIERS = new Set(['innerCircle', 'private']);

/**
 * @returns {Promise<{latitude:number, longitude:number, isDefault:boolean}>}
 */
const viewerCenter = async (userId, userData) => {
  const coords = await effectiveCoords(userId, userData).catch(() => null);
  if (coords) return { latitude: coords.latitude, longitude: coords.longitude, isDefault: false };
  return { latitude: DEFAULT_LOCATION.latitude, longitude: DEFAULT_LOCATION.longitude, isDefault: true };
};

/**
 * How many places each person saved within 80 km of `center`.
 * @returns {Promise<Map<string, number>>} userId → count
 */
const localSaverCounts = async (center) => {
  const point = [center.latitude, center.longitude];
  const bounds = geofire.geohashQueryBounds(point, RADIUS_M);
  const snaps = await Promise.all(bounds.map(([start, end]) => db.collection(COLLECTIONS.PLACES)
    .orderBy('geohash').startAt(start).endAt(end)
    .select('addedBy', 'location', 'privacy', 'deletedAt')
    .limit(PER_QUERY)
    .get()));
  const counts = new Map();
  const seen = new Set();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const p = doc.data();
      if (!p.addedBy || p.deletedAt || HIDDEN_TIERS.has(p.privacy)) continue;
      const c = p.location && p.location.coordinates; // GeoJSON [lng, lat]
      if (!Array.isArray(c) || c.length !== 2) continue;
      if (geofire.distanceBetween([c[1], c[0]], point) * 1000 > RADIUS_M) continue;
      counts.set(p.addedBy, (counts.get(p.addedBy) || 0) + 1);
    }
  }
  return counts;
};

/**
 * Core people first, then people with favorites nearby (most first), then
 * everyone else by place count. Pure; candidates carry `_isCore`,
 * `_localCount` and `_actualPlacesCount`.
 */
const rankSuggestedUsers = (candidates) => [...candidates].sort((a, b) => {
  if (a._isCore !== b._isCore) return a._isCore ? -1 : 1;
  const local = (b._localCount || 0) - (a._localCount || 0);
  if (local !== 0) return local;
  return (b._actualPlacesCount || 0) - (a._actualPlacesCount || 0);
});

module.exports = { viewerCenter, localSaverCounts, rankSuggestedUsers };
