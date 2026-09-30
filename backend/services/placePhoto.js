const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

// The one picture an activity row shows for a place.
//
// Photos arrive in two shapes — a bare URL string (save records) or an
// attributed object `{ id, url, … }` (venue records) — and the check-in path
// only understood strings, so a venue whose photos were all attributed gave
// every check-in there a blank thumbnail (Joey at Walmart, 2026-09-30).
// Raw Google Places photo URLs are skipped: those bill per render.

const isUsable = (url) => typeof url === 'string' && url.length > 0 && !url.includes('maps.googleapis.com');

const urlOf = (photo) => {
  if (typeof photo === 'string') return photo;
  return (photo && typeof photo.url === 'string') ? photo.url : null;
};

/** First usable URL in a photos array of either shape, or null. */
const firstPhotoUrl = (photos) => {
  for (const photo of Array.isArray(photos) ? photos : []) {
    const url = urlOf(photo);
    if (isUsable(url)) return url;
  }
  return null;
};

/** A venue record's picture: the owner-chosen cover first, then its photos. */
const venuePhotoUrl = (venue) => {
  if (!venue) return null;
  if (isUsable(venue.coverPhotoUrl)) return venue.coverPhotoUrl;
  return firstPhotoUrl(venue.photos);
};

/**
 * The picture for a save, falling back to its venue. Pass whatever is at
 * hand: `save` (already-loaded data) or `placeId`, and/or `globalPlaceId`
 * (used when the save hasn't been linked to its venue yet). Never throws.
 */
const resolvePlacePhoto = async ({ placeId = null, save = null, globalPlaceId = null } = {}) => {
  const db = getFirestore();
  try {
    let data = save;
    if (!data && placeId) {
      const doc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      data = doc.exists ? doc.data() : null;
    }
    const own = data ? firstPhotoUrl(data.photos) : null;
    if (own) return own;
    const venueId = (data && data.globalPlaceId) || globalPlaceId;
    if (!venueId) return null;
    const venue = await db.collection('globalPlaces').doc(venueId).get();
    return venue.exists ? venuePhotoUrl(venue.data()) : null;
  } catch (e) {
    console.error('⚠️ resolvePlacePhoto failed:', e.message);
    return null;
  }
};

module.exports = { firstPhotoUrl, venuePhotoUrl, resolvePlacePhoto };
