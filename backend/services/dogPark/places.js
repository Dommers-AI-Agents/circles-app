// backend/services/dogPark/places.js
//
// Favorite dog places: a place picked in My Dogs is saved like any save, into
// the person's "Dog spots" circle (found or made on first use), so it shows on
// their map and profile like every other favorite.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { clean } = require('../../utils/text');
const { nowIso } = require('../../utils/ids');
const { COLLECTIONS, createCircle, createPlace } = require('../../models/FirestoreModels');

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

async function savePlace(uid, body) {
  await s.loadUser(uid);
  const place = parsePlace(body);
  const circleId = await findOrCreateCircle(uid);
  const places = s.db().collection(COLLECTIONS.PLACES);
  // Already in the circle (same name at the same spot): nothing to add
  const same = await places.where('circleId', '==', circleId).where('name', '==', place.name).limit(5).get();
  const already = same.docs.find((d) => {
    const c = d.data().location && d.data().location.coordinates;
    return !d.data().deletedAt && Array.isArray(c) && Math.abs(c[1] - place.lat) < 0.0005 && Math.abs(c[0] - place.lng) < 0.0005;
  });
  if (already) return { placeId: already.id, circleId, alreadySaved: true };
  const placeData = createPlace({
    name: place.name,
    address: place.address,
    location: { type: 'Point', coordinates: [place.lng, place.lat] },
    category: place.category
  }, circleId, uid);
  const ref = await places.add(placeData);
  // Every save path links the canonical venue record (CLAUDE.md)
  await require('../globalPlaceResolver').ensureGlobalPlaceLink(await ref.get()).catch((err) =>
    console.error('🐶 global link failed:', err.message));
  await s.db().collection(COLLECTIONS.CIRCLES).doc(circleId).update({
    placesCount: s.fieldValue().increment(1),
    updatedAt: nowIso()
  }).catch(() => {});
  return { placeId: ref.id, circleId, alreadySaved: false };
}

module.exports = { savePlace, parsePlace, findOrCreateCircle, CIRCLE_NAME };
