// backend/services/categorySweep.js
//
// The nightly category sweep: classify the venues that nothing else could.
//
// Google types, Apple POI and text inference resolve the vast majority of
// categories for free. The handful they can't ("The Anchor", "Mercantile" — no
// type data, a name that gives nothing away) get flagged `needsCategoryReview`
// at save time by globalPlaceResolver, and this sends them to the LLM tier in
// batches. Without it those venues sit in Other forever and the share of
// uncategorized places creeps back up as the app grows.
//
// Cost shape: once per VENUE ever (not per save), and only the tail — measured
// at ~$0.00045/venue on Haiku. The two invariants that keep it that way are
// re-asserted here before anything is sent, so a bad query or a future edit
// can't quietly turn this into a full-corpus run.
//
// Called by scripts/sweep-category-review.js (CLI) and POST /api/tasks/
// sweep-categories (Cloud Scheduler). Returns a report; never throws for
// per-venue failures.

const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const classifier = require('./categoryClassifier');

const db = getFirestore();

// Conservative per-run ceiling. The tail is small by construction, so hitting
// this means something upstream is wrong — the report says so out loud rather
// than silently truncating.
const DEFAULT_MAX_PLACES = 500;
const DEFAULT_BATCH_SIZE = 20;

const signalsOf = (d) => ({
  googlePrimaryType: d.googlePrimaryType,
  googleTypes: d.googleTypes,
  applePoiCategory: d.applePoiCategory,
  name: d.name,
  description: d.description,
  address: d.address
});

// Sync a venue's category down to its `places` cache copies — those are what
// the geo/list/browse queries actually filter on.
async function syncCacheToPlaces(globalPlaceId, category, now) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  if (siblings.empty) return 0;
  const batch = db.batch();
  siblings.docs.forEach(doc => batch.update(doc.ref, { category, updatedAt: now }));
  await batch.commit();
  return siblings.size;
}

/**
 * @param {object} opts
 * @param {boolean} opts.dryRun    report only; never calls the API or writes
 * @param {number}  opts.maxPlaces hard cap on venues sent this run
 * @param {number}  opts.batchSize venues per LLM call (amortizes the prompt)
 * @returns {Promise<object>} report
 */
async function runCategorySweep({
  dryRun = false,
  maxPlaces = DEFAULT_MAX_PLACES,
  batchSize = DEFAULT_BATCH_SIZE
} = {}) {
  const enabled = classifier.isEnabled();
  const report = {
    enabled,
    dryRun,
    model: classifier.MODEL,
    flagged: 0,
    eligible: 0,
    staleFlagsCleared: 0,
    sent: 0,
    capped: false,
    skippedByCap: 0,
    calls: 0,
    resolved: 0,
    unresolved: 0,
    failed: 0,
    cacheSynced: 0,
    usage: { input_tokens: 0, output_tokens: 0 },
    costUSD: 0,
    sample: []
  };

  if (!enabled && !dryRun) return report;

  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
    .where('needsCategoryReview', '==', true)
    .get();
  report.flagged = snap.size;

  // Re-assert both invariants regardless of what the flag says. The flag is a
  // hint written at save time; these two conditions are the actual contract:
  //   tail-only      — the venue is still uncategorized
  //   once-per-venue — it has never been sent to the model
  const now = new Date().toISOString();
  const eligible = [];
  const stale = [];
  for (const doc of snap.docs) {
    const d = doc.data();
    const isTail = (d.category || 'other') === 'other';
    const neverClassified = !d.categoryClassifiedAt;
    if (isTail && neverClassified) eligible.push(doc);
    else stale.push(doc);   // resolved some other way since it was flagged
  }
  report.eligible = eligible.length;

  // Clear flags on venues that no longer need review so the set doesn't grow.
  if (stale.length && !dryRun) {
    const batch = db.batch();
    stale.forEach(doc => batch.update(doc.ref, { needsCategoryReview: false }));
    await batch.commit();
    report.staleFlagsCleared = stale.length;
  }

  if (!eligible.length) return report;

  const targets = eligible.slice(0, maxPlaces);
  report.sent = targets.length;
  if (targets.length < eligible.length) {
    report.capped = true;
    report.skippedByCap = eligible.length - targets.length;
  }

  if (dryRun) {
    report.calls = Math.ceil(targets.length / batchSize);
    report.sample = targets.slice(0, 25).map(doc => ({
      id: doc.id,
      name: doc.data().name || 'Unnamed',
      address: doc.data().address || null
    }));
    return report;
  }

  const places = targets.map(doc => ({ id: doc.id, ...signalsOf(doc.data()) }));
  const { byId, usage, calls } = await classifier.classifyPlaces(places, { batchSize });
  report.usage = usage;
  report.calls = calls;
  report.costUSD = classifier.estimateCostUSD(usage);

  for (const doc of targets) {
    const r = byId.get(doc.id);
    try {
      if (r && r.category !== 'other') {
        const prior = doc.data();
        await doc.ref.update({
          category: r.category,
          categorySource: 'llm',
          categoryConfidence: r.confidence != null ? r.confidence : null,
          categoryBefore: prior.categoryBefore != null ? prior.categoryBefore : (prior.category || 'other'),
          categoryClassifiedAt: now,
          needsCategoryReview: false,
          updatedAt: now
        });
        report.resolved++;
        report.cacheSynced += await syncCacheToPlaces(doc.id, r.category, now);
      } else {
        // The model couldn't place it either. Stamp classifiedAt anyway so we
        // never pay for this venue twice.
        await doc.ref.update({
          categoryClassifiedAt: now,
          needsCategoryReview: false,
          updatedAt: now
        });
        report.unresolved++;
      }
    } catch (e) {
      report.failed++;
      console.error(`   ❌ [categorySweep] ${doc.id}: ${e.message}`);
    }
  }

  return report;
}

module.exports = { runCategorySweep, DEFAULT_MAX_PLACES, DEFAULT_BATCH_SIZE };
