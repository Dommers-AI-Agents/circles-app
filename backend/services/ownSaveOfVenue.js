// backend/services/ownSaveOfVenue.js
//
// "Has this user already saved this venue?" — shared by check-ins (attach to
// the existing save) and Add Place (say "you already have it in <circle>").
//
// Add Place used to answer it on the phone by downloading every place in
// every one of the user's circles (1 + N requests) before it would save —
// the "checking to see if the place exists" hang on a weak signal (Wes,
// 2026-10-04). One server lookup inside the save replaces that.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { findCanonicalByNameAndLocation, haversineMeters } = require('./globalPlaceResolver');

const db = getFirestore();

// A second Crunch Fitness across town is a new place, not the old save
const SAME_VENUE_RADIUS_METERS = 200;

const coordsOf = (location) => {
  if (!location) return null;
  if (Array.isArray(location.coordinates) && location.coordinates.length === 2) {
    return { lng: location.coordinates[0], lat: location.coordinates[1] };
  }
  if (typeof location.latitude === 'number' && typeof location.longitude === 'number') {
    return { lng: location.longitude, lat: location.latitude };
  }
  return null;
};

/** Pure: of same-named saves, the one at this spot (or an unlocated legacy one). */
const pickByDistance = (docs, here) => {
  let best = null;
  let bestDistance = Infinity;
  let unlocated = null; // legacy exact-name fallback when distance can't be judged
  docs.forEach((doc) => {
    const there = coordsOf(doc.data().location);
    if (!here || !there) {
      if (!unlocated) unlocated = doc;
      return;
    }
    const distance = haversineMeters(here.lat, here.lng, there.lat, there.lng);
    if (distance <= SAME_VENUE_RADIUS_METERS && distance < bestDistance) {
      best = doc;
      bestDistance = distance;
    }
  });
  return best || unlocated;
};

const firstLive = async (query) => {
  const snap = await query.where('deletedAt', '==', null).limit(10).get();
  return snap.empty ? [] : snap.docs;
};

/**
 * The user's live save of a venue, or null. Tries, cheapest first: the
 * canonical venue id, the Google place id, then the exact name near the spot.
 */
async function findExistingSaveOfVenue({ userId, globalPlaceId, googlePlaceId, placeName, location }) {
  const places = db.collection(COLLECTIONS.PLACES).where('addedBy', '==', userId);
  if (globalPlaceId) {
    const byVenue = await firstLive(places.where('globalPlaceId', '==', globalPlaceId));
    if (byVenue.length) return byVenue[0];
  }
  if (googlePlaceId) {
    const byGoogle = await firstLive(places.where('googlePlaceId', '==', googlePlaceId));
    if (byGoogle.length) return byGoogle[0];
  }
  if (!placeName) return null;
  const byName = await firstLive(places.where('name', '==', placeName));
  return byName.length ? pickByDistance(byName, coordsOf(location)) : null;
}

/**
 * For a place about to be saved: the user's existing save of the same venue
 * in ANY circle, also matching a differently-worded name of the same venue
 * (the canonical record's name + proximity rules). Never throws: a failed
 * lookup must not block a save.
 */
async function findOwnSaveForNewPlace({ userId, googlePlaceId, name, location }) {
  try {
    const direct = await findExistingSaveOfVenue({ userId, googlePlaceId, placeName: name, location });
    if (direct) return direct;
    if (name && location) {
      const venue = await findCanonicalByNameAndLocation(name, location, null, { googlePlaceId: googlePlaceId || null });
      if (venue) return await findExistingSaveOfVenue({ userId, globalPlaceId: venue.id });
    }
  } catch (error) {
    console.error('⚠️ [own-save] duplicate lookup failed:', error.message);
  }
  return null;
}

module.exports = { findExistingSaveOfVenue, findOwnSaveForNewPlace, pickByDistance, coordsOf, SAME_VENUE_RADIUS_METERS };
