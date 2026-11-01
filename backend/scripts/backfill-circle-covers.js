#!/usr/bin/env node
// Real photos on every circle (Wes, 2026-11-01). Circles with no cover, an
// app icon, or a stock photo get their first place's photo (or that store's
// own photo); circles with no photo anywhere get the stock photo that fits
// them. A cover the person picked is never touched. Idempotent.
// DRY_RUN=true reports without writing; --owner <uid> does one person's circles.
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { COLLECTIONS } = require('../models/FirestoreModels');
const { firstPlacePhoto } = require('../services/circleCover');
const { stockCoverFor, isPlaceholderCover } = require('../config/circleCovers');

const DRY = process.env.DRY_RUN === 'true';
const ownerArg = process.argv.indexOf('--owner');
const onlyOwner = ownerArg > 0 ? process.argv[ownerArg + 1] : null;

(async () => {
  let query = db.collection(COLLECTIONS.CIRCLES);
  if (onlyOwner) query = query.where('owner', '==', onlyOwner);
  const snap = await query.get();
  const counts = { circles: snap.size, own: 0, placePhoto: 0, stock: 0, unchanged: 0 };
  for (const doc of snap.docs) {
    const c = doc.data();
    if (c.deletedAt) continue;
    if (!isPlaceholderCover(c)) { counts.own += 1; continue; }
    const photo = await firstPlacePhoto(c, doc.id);
    const next = photo
      ? { coverImage: photo, coverImageSource: 'place_photo' }
      : { coverImage: stockCoverFor(c), coverImageSource: 'stock' };
    if (next.coverImage === c.coverImage) { counts.unchanged += 1; continue; }
    counts[photo ? 'placePhoto' : 'stock'] += 1;
    if (!DRY) await doc.ref.update({ ...next, updatedAt: new Date().toISOString() });
  }
  console.log(`${DRY ? '[dry run] ' : ''}${JSON.stringify(counts)}`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
