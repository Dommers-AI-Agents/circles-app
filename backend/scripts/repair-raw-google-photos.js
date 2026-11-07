// backend/scripts/repair-raw-google-photos.js — one-time (2026-11-07, Canopy
// Cocktails & Garden and Charlotte Beer Garden showed empty cards): an August
// 2026 import put raw Google Place Photo links in some place libraries. Their
// references expired (HTTP 400), and because they counted as photos, the
// saves' real photos were never brought in.
// For each live venue: drop the raw links (unattributed import entries, never
// anyone's upload), bring in the saves' photos, and when the library is still
// empty, fetch one current Google photo into our storage.
//   DRY_RUN=true  node scripts/repair-raw-google-photos.js   (report only)
//   DRY_RUN=false node scripts/repair-raw-google-photos.js
require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const photos = require('../services/placePhotoService');

const DRY_RUN = String(process.env.DRY_RUN || 'true').toLowerCase() !== 'false';

(async () => {
  const db = getFirestore();
  const snap = await db.collection('globalPlaces').get();
  const todo = snap.docs.filter((d) => {
    const v = d.data();
    return !v.deletedAt && !v.mergedInto && (v.photos || []).some((p) => photos.isRawGooglePhotoUrl(photos.urlOf(p)));
  });
  console.log(`${todo.length} places with raw Google photo links (${DRY_RUN ? 'dry run' : 'live'})`);
  for (const doc of todo) {
    const venue = doc.data();
    const raw = (venue.photos || []).filter((p) => photos.isRawGooglePhotoUrl(photos.urlOf(p)));
    const saves = (await db.collection('places').where('globalPlaceId', '==', doc.id).get()).docs
      .filter((s) => !s.data().deletedAt && s.data().privacy !== 'private');
    const saveUrls = [...new Set(saves.flatMap((s) => (s.data().photos || []).map(photos.urlOf)))]
      .filter((u) => u && !photos.isRawGooglePhotoUrl(u));
    const keeps = (venue.photos || []).length - raw.length;
    console.log(`  ${venue.name}: ${raw.length} raw, ${keeps} kept, ${saveUrls.length} save photos`);
    if (DRY_RUN) continue;

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const next = (fresh.data().photos || []).filter((p) => !photos.isRawGooglePhotoUrl(photos.urlOf(p)));
      tx.update(doc.ref, { photos: next, coverPhotoUrl: photos.coverUrl(next), updatedAt: new Date().toISOString() });
    });
    const saver = saves[0] && saves[0].data().addedBy;
    if (saveUrls.length && saver) {
      await photos.adoptSavePhotos({ globalPlaceId: doc.id, user: { uid: saver }, photos: saveUrls });
    }
    const after = (await doc.ref.get()).data();
    let google = 'not needed';
    if (!photos.hasVisiblePhotos(after.photos) && after.googlePlaceId && saver) {
      const url = await require('../services/googlePlacePhoto').fetchGooglePhotoUrl({ googlePlaceId: after.googlePlaceId });
      if (url) await photos.adoptSavePhotos({ globalPlaceId: doc.id, user: { uid: saver }, photos: [url] });
      google = url ? 'added' : 'none';
    }
    const final = (await doc.ref.get()).data();
    console.log(`    ✅ cover ${final.coverPhotoUrl ? 'set' : 'NONE'}, ${photos.visiblePhotos(final.photos, null).length} visible, Google photo ${google}`);
  }
  process.exit(0);
})();
