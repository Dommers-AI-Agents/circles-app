// backend/services/circleCover.js
//
// Default circle cover: a circle with no cover image shows one of its own
// place photos instead of a blank tile (Wes, 2026-08-29). A cover the user set
// themselves is never touched; a defaulted one is stamped
// coverImageSource: 'place_photo' so it can be told apart / refreshed later.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const db = getFirestore();

/** First photo of the first place (in the circle's own order) that has one. */
async function firstPlacePhoto(circleData) {
  const ids = Array.isArray(circleData.places) ? circleData.places : [];
  // Circle order = newest first; look at a handful, then fall back to a query
  for (const id of ids.slice(0, 12)) {
    const snap = await db.collection(COLLECTIONS.PLACES).doc(id).get();
    if (!snap.exists) continue;
    const p = snap.data();
    if (p.deletedAt) continue;
    // Skip raw Google Places photo URLs — every render of those is billed
    const photo = (Array.isArray(p.photos) ? p.photos : [])
      .find(u => typeof u === 'string' && u.startsWith('https://') && !u.includes('maps.googleapis.com'));
    if (photo) return photo;
  }
  return null;
}

/**
 * Give the circle a cover if it has none. `photoUrl` (a photo that just
 * landed on one of its places) is used directly; otherwise the circle's
 * places are scanned. Best-effort — never throws.
 * @returns {Promise<string|null>} the cover now on the circle, if any
 */
async function ensureCircleCoverImage(circleId, photoUrl = null) {
  try {
    if (!circleId) return null;
    const ref = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const snap = await ref.get();
    if (!snap.exists) return null;
    const circle = snap.data();
    if (circle.coverImage) return circle.coverImage;

    const cover = photoUrl || await firstPlacePhoto(circle);
    if (!cover) return null;
    await ref.update({
      coverImage: cover,
      coverImageSource: 'place_photo',
      updatedAt: new Date().toISOString()
    });
    return cover;
  } catch (error) {
    console.error(`⚠️ ensureCircleCoverImage(${circleId}) failed (non-fatal):`, error.message);
    return null;
  }
}

module.exports = { ensureCircleCoverImage, firstPlacePhoto };
