// services/googlePhotoRehost.js
//
// Old saves (before googleEnrichment re-hosted photos) hold raw
// maps.googleapis.com photo links. Those carry the server API key in a
// client-readable doc, bill a Places Photo request on every render, and their
// photo references expire — every one left in 2026-11 answered 400, and the
// app's old "migrate on a broken image" retry scanned every save and crashed
// on the attributed `{ url, … }` photo shape (`photo.includes is not a
// function`, 2026-11-02).
//
// For each save holding such links: re-host what Google still serves, and
// replace what it doesn't with the place's CURRENT Google photos, stored in
// our storage (`fetchGooglePhotoUrls`) — a store keeps its Google pictures.
// Only when Google has nothing left is a dead link dropped. Other photos, in
// either shape, are kept in place.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { isGooglePhotoLink } = require('./placePhoto');

/** Save docs (one, or all) that still hold a Google photo link. */
async function savesWithGoogleLinks(placeId = null) {
  const col = getFirestore().collection(COLLECTIONS.PLACES);
  const docs = placeId
    ? [await col.doc(String(placeId)).get()].filter((d) => d.exists)
    : (await col.select('photos', 'name', 'googlePlaceId', 'location').get()).docs;
  return docs
    .map((d) => ({
      id: d.id, name: d.data().name, googlePlaceId: d.data().googlePlaceId || null, location: d.data().location || null,
      photos: Array.isArray(d.data().photos) ? d.data().photos : []
    }))
    .filter((p) => p.photos.some(isGooglePhotoLink));
}

/**
 * Re-host or drop every Google link. `dryRun` only reports. Returns one row
 * per save: { placeId, placeName, googleLinks, rehosted, replaced, dropped, before }.
 */
async function rehostGooglePhotos({ placeId = null, dryRun = false } = {}) {
  const saves = await savesWithGoogleLinks(placeId);
  const results = [];
  for (const save of saves) {
    const googleLinks = save.photos.filter(isGooglePhotoLink);
    const row = { placeId: save.id, placeName: save.name, googleLinks: googleLinks.length, rehosted: 0, replaced: 0, dropped: 0, before: save.photos };
    if (!dryRun) {
      const { downloadAndUploadImage } = require('./storage');
      const photos = [];
      const deadAt = [];
      for (const photo of save.photos) {
        if (!isGooglePhotoLink(photo)) { photos.push(photo); continue; }
        const url = typeof photo === 'string' ? photo : photo.url;
        const hosted = await downloadAndUploadImage(url).catch(() => null);
        if (hosted) { photos.push(typeof photo === 'string' ? hosted : { ...photo, url: hosted }); row.rehosted += 1; } else { deadAt.push(photos.length); photos.push(null); }
      }
      if (deadAt.length) {
        const { fetchGooglePhotoUrls } = require('./googlePlacePhoto');
        const fresh = await fetchGooglePhotoUrls(save, deadAt.length);
        deadAt.forEach((at, i) => { if (fresh[i]) { photos[at] = fresh[i]; row.replaced += 1; } else row.dropped += 1; });
      }
      await getFirestore().collection(COLLECTIONS.PLACES).doc(save.id).update({ photos: photos.filter(Boolean), updatedAt: new Date().toISOString() });
    }
    results.push(row);
  }
  return results;
}

module.exports = { rehostGooglePhotos, savesWithGoogleLinks };
