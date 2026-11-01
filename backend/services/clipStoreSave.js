// backend/services/clipStoreSave.js
//
// The App Clip's window scan saves the store (Wes, 2026-11-01): the person
// already said yes when they tapped Open on "Love it here? Save us.", so the
// clip saves it to their Favorite Local Spots the moment they sign in and the
// app opens on a store that's already on their map. Only the clip asks for
// this (`save: true` on POST /rewards/scan); an in-app window scan keeps its
// circle picker (the 2026-10-27 "moved places" lesson).
//
// The save goes through the core save (services/placeSaveService), the same
// path as Add Place: venue link, duplicate check across all circles, FavCoins
// and activity.

const { getFirestore } = require('../config/firebase');
const systemCircles = require('./systemCircles');
const { findOwnSaveOfStore } = require('./ownSaveOfVenue');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * The person's Favorite Local Spots. A clip signup's starter circles are made
 * in the background (newAccountService), so a scan right after signing up can
 * arrive first: wait for it briefly.
 */
async function favoriteLocalCircle(uid, { tries = 12, gapMs = 500, db = getFirestore() } = {}) {
  for (let i = 0; i < tries; i += 1) {
    const circle = await systemCircles.findOwned(uid, 'favoriteLocal', { db });
    if (circle) return circle;
    if (i < tries - 1) await sleep(gapMs);
  }
  return null;
}

/** The core save's body for a store, from its sticker venue record */
function saveBodyFor(venue, circleId) {
  const lat = venue.location && Number(venue.location.lat);
  const lng = venue.location && Number(venue.location.lng);
  const hasSpot = Number.isFinite(lat) && Number.isFinite(lng);
  return {
    circleId,
    name: venue.placeName || venue.venueName,
    // The core save needs an address; the venue record supplies the real one
    address: venue.placeAddress || (hasSpot ? `${lat.toFixed(5)}, ${lng.toFixed(5)}` : venue.venueName),
    ...(hasSpot ? { location: { type: 'Point', coordinates: [lng, lat] } } : {}),
    category: venue.category || 'restaurant',
    ...(venue.googlePlaceId ? { googlePlaceId: venue.googlePlaceId } : {}),
    ...(venue.globalPlaceId ? { globalPlaceId: venue.globalPlaceId } : {})
  };
}

/**
 * Saves the store for `user` (req.user) unless they already have it.
 * @returns {Promise<{saved: boolean, alreadySaved: boolean, savedPlace: {placeId, circleId}|null, pending?: boolean}>}
 *   pending: the save couldn't be made now (no circle yet, a plan limit,
 *   an error); the app's own save flow finishes it.
 */
async function saveStoreForClip(user, venue, { saveImpl, circleImpl } = {}) {
  const uid = user.uid;
  if (venue.isVirtual === true) return { saved: false, alreadySaved: false, savedPlace: null, pending: true };

  const existing = await findOwnSaveOfStore({ userId: uid, venue });
  if (existing) {
    return { saved: false, alreadySaved: true, savedPlace: { placeId: existing.id, circleId: existing.data().circleId || null } };
  }

  const circle = await (circleImpl || favoriteLocalCircle)(uid);
  if (!circle) {
    console.warn(`[clip-save] no Favorite Local Spots yet for ${uid}; the app finishes the save`);
    return { saved: false, alreadySaved: false, savedPlace: null, pending: true };
  }

  const save = saveImpl || require('./placeSaveService').savePlace;
  const result = await save(user, saveBodyFor(venue, circle.id));
  const payload = result.payload || {};
  if (result.status === 201 && payload.place) {
    // Activity, FavCoins and pushes, after the scan answers
    if (result.afterResponse) {
      setImmediate(() => result.afterResponse().catch((err) => console.error('[clip-save] after-save work failed:', err.message)));
    }
    return { saved: true, alreadySaved: false, savedPlace: { placeId: payload.place.id, circleId: circle.id } };
  }
  if (payload.code === 'DUPLICATE_PLACE') {
    return { saved: false, alreadySaved: true, savedPlace: payload.existingPlaceId ? { placeId: payload.existingPlaceId, circleId: payload.existingCircleId || null } : null };
  }
  console.warn(`[clip-save] save refused for ${uid} at ${venue.venueId}: ${result.status} ${payload.message || ''}`);
  return { saved: false, alreadySaved: false, savedPlace: null, pending: true };
}

module.exports = { saveStoreForClip, saveBodyFor, favoriteLocalCircle };
