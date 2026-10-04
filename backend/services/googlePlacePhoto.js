// backend/services/googlePlacePhoto.js
//
// The place's own Google photo (what you'd see on Google Maps), re-hosted in
// our storage — the default picture for a place saved without one (Wes,
// 2026-10-04: "We want a nice google maps image as the default").
//
// Cost: one Place Details (photos field) or Find Place call plus one Photo
// call, ONLY for a venue that has no photo anywhere yet — a venue someone
// already pictured reuses that for free. Never a raw googleapis URL (those
// bill per render and expose the key).

const { Client } = require('@googlemaps/google-maps-services-js');

const client = new Client({});
const apiKey = () => require('../config/config').googleMapsApiKey || null;

/** The first photo reference for a Google place, by id or by name near a spot. */
async function photoReference({ googlePlaceId, name, location }) {
  const key = apiKey();
  if (!key) return null;
  if (googlePlaceId) {
    const details = await client.placeDetails({ params: { place_id: googlePlaceId, fields: ['photos'], key }, timeout: 8000 });
    const photos = details.data && details.data.result && details.data.result.photos;
    return photos && photos.length ? photos[0].photo_reference : null;
  }
  const coords = location && Array.isArray(location.coordinates) ? location.coordinates : null;
  if (!name || !coords) return null;
  const found = await client.findPlaceFromText({
    params: {
      input: name,
      inputtype: 'textquery',
      fields: ['photos', 'place_id'],
      locationbias: `circle:200@${coords[1]},${coords[0]}`,
      key
    },
    timeout: 8000
  });
  const candidate = found.data && found.data.candidates && found.data.candidates[0];
  return candidate && candidate.photos && candidate.photos.length ? candidate.photos[0].photo_reference : null;
}

/**
 * A stored URL of the place's Google photo, or null when Google has none
 * (or the lookup failed — the caller falls back to Look Around / a map).
 */
async function fetchGooglePhotoUrl({ googlePlaceId, name, location }) {
  try {
    const reference = await photoReference({ googlePlaceId, name, location });
    if (!reference) return null;
    const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=1200&photoreference=${reference}&key=${apiKey()}`;
    const { downloadAndUploadMultipleImages } = require('./storage');
    const { uploadedUrls } = await downloadAndUploadMultipleImages([photoUrl]);
    return (uploadedUrls && uploadedUrls[0]) || null;
  } catch (error) {
    console.error('⚠️ [google-photo] lookup failed:', error.message);
    return null;
  }
}

module.exports = { fetchGooglePhotoUrl };
