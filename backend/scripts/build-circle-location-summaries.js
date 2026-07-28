// Build/rebuild the per-circle location summaries that power the network-wide
// browse tree. Reads every (non-deleted) place once, groups by circle, and
// writes circleLocationSummaries/{circleId}. Idempotent — safe to re-run; it's
// also the nightly-drift corrector.
//
// Usage:
//   DRY_RUN=true node scripts/build-circle-location-summaries.js   # report only
//   node scripts/build-circle-location-summaries.js                # write

const admin = require('firebase-admin');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

if (!admin.apps.length) {
  const serviceAccount = require(path.join(__dirname, '../config/firebase-service-account.json'));
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'circles-app-83b67.firebasestorage.app'
  });
}

const { getFirestore } = require('../config/firebase');
const { serializeDoc } = require('../models/FirestoreModels');
const { summarizeCirclePlaces } = require('../services/browseAggregation');
const { COLLECTION } = require('../services/circleLocationSummary');

const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';

async function main() {
  console.log('🚀 Building per-circle location summaries');
  console.log(`📊 Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE RUN'}`);

  const snap = await db.collection('places').get();
  const byCircle = new Map();
  let live = 0;
  snap.docs.forEach(doc => {
    const p = serializeDoc(doc);
    if (p.deletedAt || !p.circleId) return;
    live++;
    if (!byCircle.has(p.circleId)) byCircle.set(p.circleId, []);
    byCircle.get(p.circleId).push(p);
  });
  console.log(`📋 ${snap.size} place docs, ${live} live, across ${byCircle.size} circles`);

  const now = new Date().toISOString();
  let written = 0, placedTotal = 0, unplacedTotal = 0;

  for (const [circleId, places] of byCircle) {
    const summary = summarizeCirclePlaces(places);
    placedTotal += Object.values(summary.cityCounts).reduce((a, b) => a + b, 0);
    unplacedTotal += summary.unplacedCount;
    if (!DRY_RUN) {
      await db.collection(COLLECTION).doc(circleId).set({ ...summary, updatedAt: now });
      written++;
      if (written % 100 === 0) { console.log(`   ... ${written}/${byCircle.size}`); await new Promise(r => setTimeout(r, 50)); }
    }
  }

  console.log('\n📊 Summary');
  console.log(`   circles summarized: ${byCircle.size}`);
  console.log(`   placed saves counted: ${placedTotal}, unplaced: ${unplacedTotal}`);
  if (!DRY_RUN) console.log(`   summary docs written: ${written}`);
}

main().then(() => process.exit(0)).catch(err => { console.error('💥 Build failed:', err); process.exit(1); });
