// Backfill script: re-derive `category` for canonical globalPlaces that are
// currently 'other'/null, using the shared cascade (deterministic -> text ->
// optional LLM). Non-destructive and reversible: it only touches 'other'/null
// venues, records `categoryBefore`/`categorySource`, and syncs the derived
// category to each venue's `places` cache copies. See restore-place-categories.js
// to undo.
//
// Usage:
//   DRY_RUN=true node scripts/backfill-place-categories.js            # report only, no writes
//   LIMIT=100 node scripts/backfill-place-categories.js               # process a small slice
//   CATEGORY_LLM_ENABLED=true ANTHROPIC_API_KEY=... node scripts/backfill-place-categories.js
//
// Env:
//   DRY_RUN=true            report only
//   LIMIT=N                 only process the first N 'other'/null venues
//   CATEGORY_LLM_ENABLED    turn on the tier-3 LLM classifier for the residual tail
//   MAX_LLM_PLACES=N        hard cap on how many places are sent to the LLM (cost guard)
//   LLM_BATCH_SIZE=N        places per LLM call (default 20)

const admin = require('firebase-admin');
const path = require('path');

// Load backend/.env so ANTHROPIC_API_KEY (and other config) are available when
// running the optional LLM tier locally.
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

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
const { deriveCategory } = require('../services/placeCategoryDerivation');
const classifier = require('../services/categoryClassifier');

const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';
const LIMIT = process.env.LIMIT ? parseInt(process.env.LIMIT, 10) : Infinity;
const MAX_LLM_PLACES = process.env.MAX_LLM_PLACES ? parseInt(process.env.MAX_LLM_PLACES, 10) : Infinity;
const LLM_BATCH_SIZE = process.env.LLM_BATCH_SIZE ? parseInt(process.env.LLM_BATCH_SIZE, 10) : 20;

const signalsOf = (d) => ({
  googlePrimaryType: d.googlePrimaryType,
  googleTypes: d.googleTypes,
  applePoiCategory: d.applePoiCategory,
  name: d.name,
  description: d.description,
  address: d.address
});

const pct = (n, total) => total ? `${((n / total) * 100).toFixed(1)}%` : '0%';

// Sync a venue's derived category down to its `places` cache copies so
// geo/list/category queries stay correct.
async function syncCacheToPlaces(globalPlaceId, category, now) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  if (siblings.empty) return 0;
  const batch = db.batch();
  siblings.docs.forEach(doc => batch.update(doc.ref, { category, updatedAt: now }));
  await batch.commit();
  return siblings.size;
}

async function main() {
  console.log('🚀 Backfilling place categories on globalPlaces');
  console.log(`📊 Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE RUN'}`);
  console.log(`🤖 LLM tier: ${classifier.isEnabled() ? `ON (${classifier.MODEL})` : 'OFF'}`);

  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).get();
  const total = snap.size;
  const otherDocs = snap.docs.filter(doc => {
    const c = doc.data().category;
    return !c || c === 'other';
  });
  console.log(`📋 ${total} venues, ${otherDocs.length} are 'other'/null (${pct(otherDocs.length, total)}) before backfill`);

  const targets = otherDocs.slice(0, LIMIT === Infinity ? otherDocs.length : LIMIT);
  if (targets.length < otherDocs.length) {
    console.log(`   ↳ limiting this run to ${targets.length} venues (LIMIT=${LIMIT})`);
  }

  // Tier 1–2: deterministic + text (free)
  const planned = [];        // { doc, category, source, confidence }
  const stillOther = [];
  for (const doc of targets) {
    const r = deriveCategory(signalsOf(doc.data()));
    if (r.category !== 'other') planned.push({ doc, ...r });
    else stillOther.push(doc);
  }
  console.log(`\n🧭 Deterministic + text resolved ${planned.length}/${targets.length}; ${stillOther.length} remain 'other'`);

  // Tier 3: LLM on the residual tail (opt-in, capped)
  let llmUsage = null, llmCost = 0, llmCalls = 0, llmResolved = 0;
  if (classifier.isEnabled() && stillOther.length) {
    const capped = stillOther.slice(0, MAX_LLM_PLACES);
    if (capped.length < stillOther.length) {
      console.log(`   ⚠️ Capping LLM to ${capped.length}/${stillOther.length} venues (MAX_LLM_PLACES)`);
    }
    const places = capped.map(doc => ({ id: doc.id, ...signalsOf(doc.data()) }));
    console.log(`🤖 Classifying ${places.length} venues via LLM (batch ${LLM_BATCH_SIZE})...`);
    const { byId, usage, calls } = await classifier.classifyPlaces(places, { batchSize: LLM_BATCH_SIZE });
    llmUsage = usage; llmCalls = calls; llmCost = classifier.estimateCostUSD(usage);
    for (const doc of capped) {
      const r = byId.get(doc.id);
      if (r && r.category !== 'other') {
        planned.push({ doc, category: r.category, source: 'llm', confidence: r.confidence });
        llmResolved++;
      }
    }
    console.log(`   ✅ LLM resolved ${llmResolved}/${places.length}`);
    console.log(`   💸 Tokens: ${usage.input_tokens} in / ${usage.output_tokens} out over ${calls} calls ≈ $${llmCost.toFixed(3)}`);
  }

  // Apply
  const now = new Date().toISOString();
  if (DRY_RUN) {
    console.log('\n🔍 Sample of planned changes (first 25):');
    planned.slice(0, 25).forEach(({ doc, category, source, confidence }) => {
      console.log(`   ${doc.data().name || 'Unnamed'} : other -> ${category} (${source}${confidence != null ? ` ${confidence}` : ''})`);
    });
  } else {
    let written = 0, cacheSynced = 0, failed = 0;
    for (const [i, { doc, category, source, confidence }] of planned.entries()) {
      try {
        const prior = doc.data();
        await doc.ref.update({
          category,
          categorySource: source,
          categoryConfidence: confidence != null ? confidence : null,
          // preserve the very first prior value if a categoryBefore already exists
          categoryBefore: prior.categoryBefore != null ? prior.categoryBefore : (prior.category || 'other'),
          categoryClassifiedAt: now,
          updatedAt: now
        });
        written++;
        cacheSynced += await syncCacheToPlaces(doc.id, category, now);
      } catch (e) {
        failed++;
        console.error(`   ❌ ${doc.id}: ${e.message}`);
      }
      if ((i + 1) % 50 === 0) {
        console.log(`   ... ${i + 1}/${planned.length} written`);
        await new Promise(r => setTimeout(r, 100));
      }
    }
    console.log(`\n✅ Updated ${written} venues, synced ${cacheSynced} place cache copies, ${failed} failed`);
  }

  // Report projected/after
  const remainingOther = otherDocs.length - planned.length;
  console.log('\n📊 Summary');
  console.log(`   before: ${otherDocs.length} 'other' (${pct(otherDocs.length, total)})`);
  console.log(`   ${DRY_RUN ? 'would resolve' : 'resolved'}: ${planned.length} (deterministic/text ${planned.length - llmResolved}, llm ${llmResolved})`);
  console.log(`   ${DRY_RUN ? 'would remain' : 'remaining'}: ${remainingOther} 'other' (${pct(remainingOther, total)})`);
  if (llmUsage) console.log(`   llm spend: $${llmCost.toFixed(3)} (${llmCalls} calls)`);
}

main()
  .then(() => process.exit(0))
  .catch(err => { console.error('💥 Backfill failed:', err); process.exit(1); });
