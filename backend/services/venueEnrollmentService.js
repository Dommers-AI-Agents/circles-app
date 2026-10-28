// Enrolling a place in the sticker program from its place record alone: the
// super-user "print this store's QR codes" door, and claim approval for a
// business nobody enrolled yet. One rule for turning a place (canonical
// globalPlaces doc, or a legacy save) into the venue fields createVenue needs.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS, validateStickerVenue } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const rewardService = require('./rewardService');

const db = getFirestore();

const latLng = (location) => {
  const coords = location && location.coordinates; // GeoJSON [lng, lat]
  if (Array.isArray(coords) && coords.length === 2
      && typeof coords[0] === 'number' && typeof coords[1] === 'number') {
    return { lat: coords[1], lng: coords[0] };
  }
  if (location && typeof location.lat === 'number' && typeof location.lng === 'number') {
    return { lat: location.lat, lng: location.lng };
  }
  return null;
};

/**
 * The venue fields a place record supplies: name, address, ids, location,
 * category. Looks the id up as a globalPlaces doc first, then as a legacy
 * save (following its globalPlaceId when it has one). Null when neither
 * exists.
 */
const placeVenueFields = async (placeId, { googlePlaceId = null } = {}) => {
  if (!placeId) return null;
  const fromDoc = (data, ids) => ({
    venueName: data.name || null,
    placeName: data.name || null,
    placeAddress: data.address || null,
    googlePlaceId: data.googlePlaceId || googlePlaceId || null,
    globalPlaceId: ids.globalPlaceId || null,
    location: latLng(data.location),
    category: data.category || null
  });

  const globalDoc = await db.collection('globalPlaces').doc(placeId).get();
  if (globalDoc.exists) return fromDoc(globalDoc.data(), { globalPlaceId: globalDoc.id });

  const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
  if (!placeDoc.exists) return null;
  const save = placeDoc.data();
  if (save.globalPlaceId) {
    const linked = await db.collection('globalPlaces').doc(save.globalPlaceId).get();
    if (linked.exists) {
      const fields = fromDoc(linked.data(), { globalPlaceId: linked.id });
      // The save's own cache fills anything the venue record lacks
      fields.venueName = fields.venueName || save.name || null;
      fields.placeName = fields.venueName;
      fields.placeAddress = fields.placeAddress || save.address || null;
      fields.googlePlaceId = fields.googlePlaceId || save.googlePlaceId || null;
      fields.location = fields.location || latLng(save.location);
      fields.category = fields.category || save.category || null;
      return fields;
    }
  }
  return fromDoc(save, { globalPlaceId: save.globalPlaceId || null });
};

// Any venue already minted for this place, active or not: findVenueByPlace
// hides deactivated ones, and enrolling again would print a second set of
// codes for the same store.
const existingVenueForPlace = async (fields) => {
  const venues = db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
  for (const [field, value] of [['globalPlaceId', fields.globalPlaceId], ['googlePlaceId', fields.googlePlaceId]]) {
    if (!value) continue;
    const hit = await venues.where(field, '==', value).limit(1).get();
    if (!hit.empty) return { venueId: hit.docs[0].id, ...hit.docs[0].data() };
  }
  return null;
};

/**
 * The venue for a place, minting one when there is none. The new venue has
 * no owner and no contact: it is the store's codes, nothing more, so the real
 * owner can still claim it. Returns { venue, created }.
 */
const enrollPlace = async (placeId, { googlePlaceId = null } = {}) => {
  const fields = await placeVenueFields(placeId, { googlePlaceId });
  if (!fields) throw new ServiceError(404, 'PLACE_NOT_FOUND', 'That place no longer exists');

  const existing = await existingVenueForPlace(fields);
  if (existing) return { venue: existing, created: false };

  const payload = { ...fields, category: fields.category || 'restaurant' };
  const errors = validateStickerVenue(payload);
  if (errors.length > 0) throw new ServiceError(400, 'PLACE_INCOMPLETE', errors.join('. '));

  const venue = await rewardService.createVenue(payload);
  return { venue, created: true };
};

module.exports = { placeVenueFields, enrollPlace, latLng };
