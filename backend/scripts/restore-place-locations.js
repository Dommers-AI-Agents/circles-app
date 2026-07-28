// Rollback script: clear the derived location-lens fields (state/city/etc.) that
// the location backfill/derivation added, on both the canonical globalPlaces and
// the `places` cache copies. Location derivation is purely additive (these
// fields didn't exist before), so "restore" == clear what we set. Idempotent.
//
// Usage:
//   DRY_RUN=true node scripts/restore-place-locations.js       # report only
//   SOURCES=address node scripts/restore-place-locations.js    # only address-derived
//   node scripts/restore-place-locations.js                    # clear all derived

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

const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';
const DEFAULT_SOURCES = ['address', 'geocode', 'client'];
const SOURCES = new Set(
  (process.env.SOURCES ? process.env.SOURCES.split(',') : DEFAULT_SOURCES)
    .map(s => s.trim()).filter(Boolean)
);

const CLEARED = {
  state: null, stateCode: null, city: null, cityKey: null,
  neighborhood: null, locationSource: null, locationDerivedAt: null
};
const CACHE_CLEARED = { state: null, stateCode: null, city: null, cityKey: null, neighborhood: null };

async function clearCacheOnPlaces(globalPlaceId, now) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  if (siblings.empty) return 0;
  const batch = db.batch();
  siblings.docs.forEach(doc => batch.update(doc.ref, { ...CACHE_CLEARED, updatedAt: now }));
  await batch.commit();
  return siblings.size;
}

async function main() {
  console.log('↩️  Clearing derived place-location fields');
  console.log(`📊 Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE RUN'}`);
  console.log(`🎯 Sources: ${[...SOURCES].join(', ')}`);

  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).get();
  const targets = snap.docs.filter(doc => SOURCES.has(doc.data().locationSource));
  console.log(`📋 ${targets.length} venues to clear`);

  const now = new Date().toISOString();
  let cleared = 0, cacheCleared = 0, failed = 0;
  for (const [i, doc] of targets.entries()) {
    const d = doc.data();
    if (DRY_RUN) {
      console.log(`   ${d.name || 'Unnamed'} : clear ${d.city}, ${d.stateCode} (${d.locationSource})`);
      cleared++;
      continue;
    }
    try {
      await doc.ref.update({ ...CLEARED, updatedAt: now });
      cleared++;
      cacheCleared += await clearCacheOnPlaces(doc.id, now);
    } catch (e) {
      failed++;
      console.error(`   ❌ ${doc.id}: ${e.message}`);
    }
    if ((i + 1) % 50 === 0) {
      console.log(`   ... ${i + 1}/${targets.length}`);
      await new Promise(r => setTimeout(r, 100));
    }
  }

  console.log('\n📊 Summary');
  console.log(`   ${DRY_RUN ? 'would clear' : 'cleared'}: ${cleared}`);
  if (!DRY_RUN) console.log(`   place cache copies cleared: ${cacheCleared}, failed: ${failed}`);
}

main()
  .then(() => process.exit(0))
  .catch(err => { console.error('💥 Restore failed:', err); process.exit(1); });
