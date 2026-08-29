// backend/scripts/backfill-circle-covers.js
// Every circle without a cover image gets its first place photo as the cover
// (coverImageSource: 'place_photo'). Idempotent. DRY_RUN=true to preview.
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { COLLECTIONS } = require('../models/FirestoreModels');
const { firstPlacePhoto } = require('../services/circleCover');

const DRY_RUN = process.env.DRY_RUN === 'true';
const onlyOwner = process.argv.indexOf('--owner') > 0 ? process.argv[process.argv.indexOf('--owner') + 1] : null;

(async () => {
  let query = db.collection(COLLECTIONS.CIRCLES);
  if (onlyOwner) query = query.where('owner', '==', onlyOwner);
  const snap = await query.get();
  let candidates = 0, set = 0, noPhoto = 0;
  for (const doc of snap.docs) {
    const c = doc.data();
    if (c.coverImage || c.deletedAt) continue;
    if (!Array.isArray(c.places) || c.places.length === 0) continue;
    candidates++;
    const cover = await firstPlacePhoto(c);
    if (!cover) { noPhoto++; continue; }
    if (DRY_RUN) { console.log(`  would set "${c.name}" ← ${cover.slice(0, 60)}…`); set++; continue; }
    await doc.ref.update({ coverImage: cover, coverImageSource: 'place_photo', updatedAt: new Date().toISOString() });
    set++;
  }
  console.log(`${snap.size} circles scanned, ${candidates} without cover (with places), ${set} ${DRY_RUN ? 'would be' : ''} set, ${noPhoto} have no place photos yet${DRY_RUN ? ' [DRY RUN]' : ''}`);
  process.exit(0);
})().catch(e => { console.error('❌', e); process.exit(1); });
