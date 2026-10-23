// backend/services/dogPark/places.js
//
// Favorite dog places: a place picked in My Dogs goes through the core save
// (the same one as Add Place) into the person's "Dog spots" circle (found or
// made on first use), so it shows on their map and profile like every other
// favorite, with Google's details.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { clean } = require('../../utils/text');
const { COLLECTIONS, createCircle } = require('../../models/FirestoreModels');

const CIRCLE_NAME = 'Dog spots';
const CIRCLE_EMOJI = '🐶';

/** A place from the request. Pure. */
function parsePlace(body) {
  const b = body || {};
  const name = clean(b.name, 120);
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  if (!name) throw new ServiceError(400, 'invalid_place', 'A place needs a name');
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) {
    throw new ServiceError(400, 'invalid_place', 'A place needs a location');
  }
  return { name, address: clean(b.address, 200) || '', lat, lng, category: clean(b.category, 40) || 'other' };
}

/** The person's Dog spots circle: the flagged one, else made now (outside the circle cap, like the check-in circle). */
async function findOrCreateCircle(uid) {
  const circles = s.db().collection(COLLECTIONS.CIRCLES);
  const snap = await circles.where('owner', '==', uid).where('isDogSpotsCircle', '==', true).limit(3).get();
  const alive = snap.docs.find((d) => !d.data().deletedAt);
  if (alive) return alive.id;
  const circle = createCircle({
    name: CIRCLE_NAME,
    description: 'Dog parks, patios and everywhere dogs are welcome',
    privacy: 'public',
    icon: CIRCLE_EMOJI
  }, uid);
  const ref = await circles.add({ ...circle, icon: CIRCLE_EMOJI, isDogSpotsCircle: true });
  return ref.id;
}

/**
 * Saves the picked place through the core save (services/placeSaveService),
 * the same path as Add Place: duplicate check across ALL your circles, Google
 * details for a venue new to FavCircles, the venue link, photos, FavCoins,
 * activity. Already saved anywhere → that save comes back, nothing new.
 * Returns { placeId, circleId, circleName, alreadySaved, afterResponse? }.
 */
async function savePlace(user, body) {
  const uid = user && user.uid;
  await s.loadUser(uid);
  const place = parsePlace(body);
  const circleId = await findOrCreateCircle(uid);
  const result = await require('../placeSaveService').savePlace(user, {
    circleId,
    name: place.name,
    // The core save needs an address; Google fills the real one in
    address: place.address || `${place.lat.toFixed(5)}, ${place.lng.toFixed(5)}`,
    location: { type: 'Point', coordinates: [place.lng, place.lat] },
    category: place.category,
    // Picked from Apple Maps on the phone: resolve it to Google here, like a
    // share-extension save (canonical venue first, Google only for new ones)
    enrichFromGoogle: true
  });
  const payload = result.payload || {};
  if (result.status === 201 && payload.place) {
    return { placeId: payload.place.id, circleId, circleName: CIRCLE_NAME, alreadySaved: false, afterResponse: result.afterResponse };
  }
  if (payload.code === 'DUPLICATE_PLACE' && payload.existingPlaceId) {
    const inDogSpots = !payload.existingCircleId || payload.existingCircleId === circleId;
    return {
      placeId: payload.existingPlaceId,
      circleId: payload.existingCircleId || circleId,
      circleName: inDogSpots ? CIRCLE_NAME : (payload.existingCircleName || null),
      alreadySaved: true
    };
  }
  throw new ServiceError(result.status || 500, payload.code || (payload.upgradeRequired ? 'upgrade_required' : 'save_failed'),
    payload.message || 'Couldn’t save that place');
}

module.exports = { savePlace, parsePlace, findOrCreateCircle, CIRCLE_NAME };
