#!/usr/bin/env node
// backend/tools/backfill-system-circle-flags.js
//
// Stamps `systemKind` (and the kind's boolean, where it has one) on the
// circles the app finds for people — "Places I Follow", "Check-in Places",
// "Favorite Local Spots", "Want to Try", "Dog spots", "Places from my photos"
// — so features find them by flag, never by name (Wes, 2026-10-31).
//
// Per owner and kind it stamps exactly the circle the feature itself would
// pick (services/systemCircles.pick): a flagged one first (older marker →
// gets systemKind), else the legacy name match (starters also need
// isDefaultCircle; check-ins prefer the fullest, then oldest). Deleted
// circles never count. Idempotent: a second run stamps nothing.
//
//   DRY_RUN=true node tools/backfill-system-circle-flags.js   # counts only
//   node tools/backfill-system-circle-flags.js                # writes
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const systemCircles = require('../services/systemCircles');

const PAGE = 500;

/** Every circle, paged by document id. */
async function* allCircles(db) {
  let last = null;
  for (;;) {
    let q = db.collection(COLLECTIONS.CIRCLES).orderBy('__name__').limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.docs.length === 0) return;
    for (const doc of snap.docs) yield { id: doc.id, ...doc.data() };
    if (snap.docs.length < PAGE) return;
    last = snap.docs[snap.docs.length - 1];
  }
}

/**
 * @returns {Promise<object>} counts per kind: { alreadyFlagged, fromMarker, fromName, stamped }
 */
async function backfill({ db = getFirestore(), dryRun = false, log = console.log } = {}) {
  const byOwner = new Map();
  let scanned = 0;
  for await (const circle of allCircles(db)) {
    scanned += 1;
    if (!circle.owner) continue;
    if (!byOwner.has(circle.owner)) byOwner.set(circle.owner, []);
    byOwner.get(circle.owner).push(circle);
  }

  const counts = {};
  for (const kind of systemCircles.KIND_NAMES) counts[kind] = { alreadyFlagged: 0, fromMarker: 0, fromName: 0, stamped: 0 };

  for (const [owner, circles] of byOwner) {
    for (const kind of systemCircles.KIND_NAMES) {
      const hit = systemCircles.pick(circles, kind);
      if (!hit) continue;
      const c = counts[kind];
      if (!hit.needsStamp) { c.alreadyFlagged += 1; continue; }
      if (systemCircles.hasFlag(hit.circle, kind)) c.fromMarker += 1; else c.fromName += 1;
      if (!dryRun) {
        await systemCircles.stamp(hit.circle.id, kind, db);
        Object.assign(hit.circle, systemCircles.flagFields(kind));
      }
      c.stamped += 1;
      log(`${dryRun ? '[dry run] would stamp' : 'stamped'} ${kind} on circle ${hit.circle.id} ("${hit.circle.name}") for owner ${owner}`);
    }
  }

  log(`\n${scanned} circles, ${byOwner.size} owners${dryRun ? ' [DRY RUN — nothing written]' : ''}`);
  for (const [kind, c] of Object.entries(counts)) {
    log(`  ${kind.padEnd(15)} already flagged ${c.alreadyFlagged}, ${dryRun ? 'would stamp' : 'stamped'} ${c.stamped} (older marker ${c.fromMarker}, legacy name ${c.fromName})`);
  }
  return counts;
}

if (require.main === module) {
  require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
  require('../config/firebase').initializeFirebase();
  const dryRun = String(process.env.DRY_RUN || '').toLowerCase() === 'true';
  backfill({ dryRun })
    .then(() => process.exit(0))
    .catch((error) => { console.error('backfill failed:', error); process.exit(1); });
}

module.exports = { backfill };
