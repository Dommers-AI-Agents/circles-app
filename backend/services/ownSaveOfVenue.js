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
const { findCanonicalByNameAndLocation, haversineMeters, resolveGlobalPlace } = require('./globalPlaceResolver');

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

/**
 * A store's record (stickerVenues) → the user's live save of its place, or
 * null. Rewards ask this before offering "Save & Earn" and before paying the
 * save points, so it follows the SAME rules as Add Place's duplicate answer:
 * the canonical venue id, the Google id, then the store's name near its spot
 * (a store enrolled by hand carries no Google id at all — matching on the
 * Google id alone offered a save that Add Place then refused, Wes 2026-10-27).
 * Never throws.
 */
async function findOwnSaveOfStore({ userId, venue }) {
  if (!userId || !venue) return null;
  try {
    const here = venue.location && typeof venue.location.lat === 'number' && typeof venue.location.lng === 'number'
      ? { latitude: venue.location.lat, longitude: venue.location.lng }
      : null;
    // A name only identifies a store together with its spot: an online-only
    // brand or an unlocated venue is matched by its ids alone (a same-named
    // save across the country is not this store)
    const names = here && venue.isVirtual !== true
      ? [...new Set([venue.placeName, venue.venueName].filter(Boolean))]
      : [];

    let globalPlaceId = venue.globalPlaceId || null;
    if (!globalPlaceId && venue.googlePlaceId) {
      // Pure lookup for a Google id (no legacy doc, so nothing is backfilled)
      const { globalPlaceDoc } = await resolveGlobalPlace(venue.googlePlaceId);
      if (globalPlaceDoc) globalPlaceId = globalPlaceDoc.id;
    }
    if (!globalPlaceId && names[0] && here) {
      const canonical = await findCanonicalByNameAndLocation(
        names[0], { coordinates: [here.longitude, here.latitude] }, null, { googlePlaceId: venue.googlePlaceId || null }
      );
      if (canonical) globalPlaceId = canonical.id;
    }

    const direct = await findExistingSaveOfVenue({
      userId, globalPlaceId, googlePlaceId: venue.googlePlaceId || null, placeName: names[0] || null, location: here
    });
    if (direct) return direct;
    // The store's display name and its place's name can differ ("Sal's" vs
    // "Sal's Pizzeria"); a save under either is this store
    for (const placeName of names.slice(1)) {
      const byName = await findExistingSaveOfVenue({ userId, placeName, location: here });
      if (byName) return byName;
    }
  } catch (error) {
    console.error('⚠️ [own-save] store lookup failed:', error.message);
  }
  return null;
}

module.exports = { findExistingSaveOfVenue, findOwnSaveForNewPlace, findOwnSaveOfStore, pickByDistance, coordsOf, SAME_VENUE_RADIUS_METERS };
