// Rollback script: revert categories set by the backfill/derivation back to
// their prior value (`categoryBefore`). This is the one-command undo referenced
// in the safety plan. Idempotent, and re-syncs the `places` cache copies.
//
// By default it reverts EVERY auto-derived category (source in google/apple/
// text/llm). Narrow the scope with SOURCES to undo just one tier — e.g. undo
// only the LLM guesses and keep the free ones.
//
// Usage:
//   DRY_RUN=true node scripts/restore-place-categories.js            # report only
//   SOURCES=llm node scripts/restore-place-categories.js            # revert only LLM-set categories
//   SOURCES=text,llm node scripts/restore-place-categories.js       # revert text + LLM
//   node scripts/restore-place-categories.js                        # revert all auto-derived

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
const DEFAULT_SOURCES = ['google', 'apple', 'text', 'llm'];
const SOURCES = new Set(
  (process.env.SOURCES ? process.env.SOURCES.split(',') : DEFAULT_SOURCES)
    .map(s => s.trim()).filter(Boolean)
);

async function syncCacheToPlaces(globalPlaceId, category, now) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  if (siblings.empty) return 0;
  const batch = db.batch();
  siblings.docs.forEach(doc => batch.update(doc.ref, { category, updatedAt: now }));
  await batch.commit();
  return siblings.size;
}

async function main() {
  console.log('↩️  Restoring place categories to their prior values');
  console.log(`📊 Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE RUN'}`);
  console.log(`🎯 Reverting sources: ${[...SOURCES].join(', ')}`);

  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).get();
  const targets = snap.docs.filter(doc => {
    const d = doc.data();
    // Only revert what WE set and where we recorded a prior value.
    return SOURCES.has(d.categorySource) && d.categoryBefore != null && d.category !== d.categoryBefore;
  });
  console.log(`📋 ${targets.length} venues to revert`);

  const now = new Date().toISOString();
  let reverted = 0, cacheSynced = 0, failed = 0;

  for (const [i, doc] of targets.entries()) {
    const d = doc.data();
    const back = d.categoryBefore;
    if (DRY_RUN) {
      console.log(`   ${d.name || 'Unnamed'} : ${d.category} (${d.categorySource}) -> ${back}`);
      reverted++;
      continue;
    }
    try {
      await doc.ref.update({
        category: back,
        // Clear our derivation stamps so the record looks un-derived again.
        categorySource: back === 'other' ? null : 'client',
        categoryConfidence: null,
        categoryBefore: null,
        categoryClassifiedAt: null,
        updatedAt: now
      });
      reverted++;
      cacheSynced += await syncCacheToPlaces(doc.id, back, now);
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
  console.log(`   ${DRY_RUN ? 'would revert' : 'reverted'}: ${reverted}`);
  if (!DRY_RUN) console.log(`   place cache copies synced: ${cacheSynced}, failed: ${failed}`);
}

main()
  .then(() => process.exit(0))
  .catch(err => { console.error('💥 Restore failed:', err); process.exit(1); });
