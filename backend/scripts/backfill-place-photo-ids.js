#!/usr/bin/env node
// backend/scripts/backfill-place-photo-ids.js
//
// Gives every globalPlaces library photo an id. Photos added Jun–Sep 2025,
// before library entries carried ids, were stored without one; every per-photo
// action keys on it (like, report, remove, set cover, reorder), so those
// photos showed no heart and couldn't be reported (Wes, 2026-11-12: Renee's
// photo at Windmill Winery had no heart, his own did).
//
// Idempotent: entries that already have an id are untouched. One transaction
// per venue, so a concurrent like/upload can't be overwritten.
//   DRY_RUN=false node scripts/backfill-place-photo-ids.js   (default: dry run)
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const { newId } = require('../utils/ids');

const DRY_RUN = process.env.DRY_RUN !== 'false';
const db = getFirestore();

const needsId = (p) => p && typeof p === 'object' && !p.id && p.url;

async function main() {
  console.log(DRY_RUN ? '🔍 DRY RUN (DRY_RUN=false to write)' : '✍️  WRITING');
  const stats = { venues: 0, venuesFixed: 0, photosFixed: 0, stringEntries: 0 };
  let last = null;
  for (;;) {
    let q = db.collection('globalPlaces').select('photos', 'name').limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      stats.venues++;
      const photos = doc.data().photos || [];
      stats.stringEntries += photos.filter((p) => typeof p === 'string').length;
      const missing = photos.filter(needsId).length;
      if (!missing) continue;
      stats.venuesFixed++;
      stats.photosFixed += missing;
      console.log(`${doc.id}  ${doc.data().name || ''}  +${missing} id(s)`);
      if (DRY_RUN) continue;
      await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        const list = (fresh.data().photos || []).map((p) => (needsId(p) ? { ...p, id: newId() } : p));
        tx.update(doc.ref, { photos: list });
      });
    }
    last = snap.docs[snap.docs.length - 1];
  }
  console.log(stats);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
