// A store's cover photo, as print and App Clip artwork use it: the canonical
// place's chosen cover, else its first photo. Best-effort: null when there's
// none or it can't be fetched, and the artwork draws without it.
const sharp = require('sharp');

async function coverUrlFor(venue) {
  if (!venue || !venue.globalPlaceId) return null;
  const { getFirestore } = require('../config/firebase');
  const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
  const placePhotos = require('./placePhotoService');
  const doc = await getFirestore().collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(venue.globalPlaceId).get();
  if (!doc.exists) return null;
  const data = doc.data();
  return data.coverPhotoUrl || placePhotos.coverUrl(data.photos || []) || null;
}

/** The photo cropped to `width` × `height` px (attention-centred) as JPEG. */
async function coverJPEG(venue, width, height) {
  try {
    const url = await coverUrlFor(venue);
    if (!url) return null;
    const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    return await sharp(buf).resize(Math.round(width), Math.round(height), { fit: 'cover', position: 'attention' })
      .jpeg({ quality: 88 }).toBuffer();
  } catch (error) {
    console.warn('⚠️ Store cover photo unavailable, drawing without it:', error.message);
    return null;
  }
}

module.exports = { coverUrlFor, coverJPEG };
