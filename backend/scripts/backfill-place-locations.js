// Backfill script: derive State/City (location lens) for canonical globalPlaces
// from their stored address string. Free (no geocoding), idempotent, and
// reversible (restore-place-locations.js). Non-destructive: only touches venues
// that don't already have a stateCode. Places that can't be resolved stay
// Unplaced (state null) so their pins remain listable.
//
// Usage:
//   DRY_RUN=true node scripts/backfill-place-locations.js       # report only
//   LIMIT=100 node scripts/backfill-place-locations.js          # small slice
//   node scripts/backfill-place-locations.js                    # live run

const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const serviceAccountPath = path.join(__dirname, '../config/firebase-service-account.json');
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'circles-app-83b67.firebasestorage.app'
  });
}

const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { deriveLocation } = require('../services/placeLocationDerivation');

const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';
const LIMIT = process.env.LIMIT ? parseInt(process.env.LIMIT, 10) : Infinity;
const pct = (n, total) => total ? `${((n / total) * 100).toFixed(1)}%` : '0%';

async function syncCacheToPlaces(globalPlaceId, fields, now) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  if (siblings.empty) return 0;
  const batch = db.batch();
  siblings.docs.forEach(doc => batch.update(doc.ref, { ...fields, updatedAt: now }));
  await batch.commit();
  return siblings.size;
}

async function main() {
  console.log('🚀 Backfilling place locations (State/City) on globalPlaces');
  console.log(`📊 Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE RUN'}`);

  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).get();
  const total = snap.size;
  // Never derived yet (no stateCode). Placed docs are skipped -> idempotent.
  const targets = snap.docs
    .filter(doc => !doc.data().stateCode)
    .slice(0, LIMIT === Infinity ? undefined : LIMIT);
  console.log(`📋 ${total} venues; ${targets.length} without a stateCode to derive`);

  const now = new Date().toISOString();
  let placed = 0, unplaced = 0, written = 0, cacheSynced = 0, failed = 0;
  const sample = [];

  for (const [i, doc] of targets.entries()) {
    const d = doc.data();
    const loc = deriveLocation({ address: d.address, location: d.location, neighborhood: d.neighborhood });

    if (!loc.placed) { unplaced++; continue; }
    placed++;
    if (sample.length < 25) sample.push(`${d.name || 'Unnamed'} : ${d.address || '(no address)'} -> ${loc.city}, ${loc.stateCode}`);

    if (DRY_RUN) continue;

    const venueFields = {
      state: loc.state, stateCode: loc.stateCode, city: loc.city,
      cityKey: loc.cityKey, neighborhood: loc.neighborhood,
      locationSource: loc.source, locationDerivedAt: now
    };
    try {
      await doc.ref.update({ ...venueFields, updatedAt: now });
      written++;
      cacheSynced += await syncCacheToPlaces(doc.id, {
        state: loc.state, stateCode: loc.stateCode, city: loc.city,
        cityKey: loc.cityKey, neighborhood: loc.neighborhood
      }, now);
    } catch (e) {
      failed++;
      console.error(`   ❌ ${doc.id}: ${e.message}`);
    }
    if ((i + 1) % 50 === 0) {
      console.log(`   ... ${i + 1}/${targets.length}`);
      await new Promise(r => setTimeout(r, 100));
    }
  }

  if (DRY_RUN) {
    console.log('\n🔍 Sample of resolutions (first 25):');
    sample.forEach(s => console.log(`   ${s}`));
  }

  console.log('\n📊 Summary');
  console.log(`   ${DRY_RUN ? 'would place' : 'placed'}: ${placed} (${pct(placed, targets.length)} of targets)`);
  console.log(`   unplaced (no US state in address): ${unplaced} (${pct(unplaced, targets.length)})`);
  if (!DRY_RUN) console.log(`   venues written: ${written}, place cache copies synced: ${cacheSynced}, failed: ${failed}`);
}

main()
  .then(() => process.exit(0))
  .catch(err => { console.error('💥 Backfill failed:', err); process.exit(1); });
