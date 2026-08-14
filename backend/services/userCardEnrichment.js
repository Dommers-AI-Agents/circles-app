// backend/services/userCardEnrichment.js
// Shared "user card" enrichment for every people surface (Discover, Popular,
// My People, following lists): place counts come from getPlaceCountMap, and
// this module adds the location story. A user with no profile location gets an
// ASSUMED one from the places they save — majority city for display, median
// coordinates for distance — cached on the user doc (assumedLocation) so the
// derivation runs about once a week per user, not once per page load.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();
const CACHE_MS = 7 * 24 * 60 * 60 * 1000;

// Best-effort "City, ST" from a saved place's address string
// ("123 Main St, Charlotte, NC 28202, USA" -> "Charlotte, NC").
const cityFromAddress = (address) => {
  if (!address || typeof address !== 'string') return null;
  const parts = address.split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length < 3) return null;
  // City sits two from the end when a country trails the state+zip.
  const city = parts[parts.length - 3];
  if (!city || /\d/.test(city)) return null;
  const stateToken = (parts[parts.length - 2] || '').split(/\s+/)[0];
  const state = /^[A-Z]{2}$/.test(stateToken) ? stateToken : null;
  return state ? `${city}, ${state}` : city;
};

const median = (nums) => {
  if (nums.length === 0) return null;
  const sorted = [...nums].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
};

const isFresh = (assumed) =>
  !!(assumed && assumed.updatedAt && (Date.now() - new Date(assumed.updatedAt).getTime()) < CACHE_MS);

// Compute { city, latitude, longitude } from up to 40 of the user's saved
// places. Median coordinates resist outliers (one vacation save shouldn't
// move someone across the country). Null when they have no places.
const computeAssumedLocation = async (userId) => {
  const snap = await db.collection(COLLECTIONS.PLACES)
    .where('addedBy', '==', userId)
    .limit(40)
    .get();
  if (snap.empty) return null;

  const votes = new Map();
  const lats = [];
  const lngs = [];
  snap.docs.forEach((d) => {
    const p = d.data();
    const city = cityFromAddress(p.address);
    if (city) votes.set(city, (votes.get(city) || 0) + 1);
    const coords = p.location && p.location.coordinates; // GeoJSON [lng, lat]
    if (Array.isArray(coords) && coords.length === 2
        && Number.isFinite(coords[0]) && Number.isFinite(coords[1])) {
      lngs.push(coords[0]);
      lats.push(coords[1]);
    }
  });

  const top = [...votes.entries()].sort((a, b) => b[1] - a[1])[0];
  const city = top ? top[0] : null;
  const latitude = median(lats);
  const longitude = median(lngs);
  if (!city && latitude === null) return null;
  return { city, latitude, longitude };
};

// Read-through cache: the user doc's assumedLocation if fresh, else compute
// and write back (best-effort — a failed cache write only costs a recompute).
const getAssumedLocation = async (userId, userData = null) => {
  const cached = userData && userData.assumedLocation;
  if (isFresh(cached)) return cached;

  try {
    const fresh = await computeAssumedLocation(userId);
    if (fresh) {
      fresh.updatedAt = new Date().toISOString();
      db.collection(COLLECTIONS.USERS).doc(userId)
        .update({ assumedLocation: fresh })
        .catch(() => {});
      return fresh;
    }
  } catch (e) {
    console.warn(`⚠️ assumedLocation compute failed for ${userId}:`, e.message);
  }
  return cached || null;
};

// Best coordinates we have for a user: a real GPS ping first, then the
// places-derived assumption.
const effectiveCoords = async (userId, userData) => {
  const gps = userData && userData.lastKnownLocation;
  if (gps && Number.isFinite(gps.latitude) && Number.isFinite(gps.longitude)) {
    return { latitude: gps.latitude, longitude: gps.longitude, source: 'gps' };
  }
  const assumed = await getAssumedLocation(userId, userData);
  if (assumed && Number.isFinite(assumed.latitude) && Number.isFinite(assumed.longitude)) {
    return { latitude: assumed.latitude, longitude: assumed.longitude, source: 'places' };
  }
  return null;
};

// Decorate a PAGE of user cards (never a whole candidate pool): fill a
// missing `location` with the assumed city, and say out loud when someone is
// recently active — fresh activity is the strongest signal a follow will be
// worth it.
const decorateUserCards = async (users, { activityReason = true } = {}) => {
  const weekAgo = Date.now() - CACHE_MS;
  await Promise.all(users.map(async (u) => {
    if (activityReason && !u.suggestionReason && u.lastActive
        && new Date(u.lastActive).getTime() > weekAgo) {
      u.suggestionReason = '⚡ Active this week';
    }
    // "Show my city" preference: strip the location line entirely — no
    // profile location, no places-derived assumption
    if (u.preferences && u.preferences.showLocation === false) {
      u.location = null;
      return;
    }
    if (u.location) return;
    const assumed = await getAssumedLocation(u.id, u);
    if (assumed && assumed.city) u.location = assumed.city;
  }));
};

module.exports = {
  cityFromAddress,
  getAssumedLocation,
  effectiveCoords,
  decorateUserCards,
  isFreshAssumedLocation: isFresh
};
