// backend/scripts/cleanup-checkin-circle-dups.js
// The 2026-07 check-in bug left some users with a duplicate empty
// "Check-in Places" circle next to the real (isCheckInCircle: true) one.
// Delete the EMPTY unflagged duplicates only. DRY_RUN=true to preview.
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';

(async () => {
  const snap = await db.collection('circles').where('name', '==', 'Check-in Places').get();
  const byOwner = new Map();
  snap.forEach(doc => {
    const owner = doc.data().owner;
    if (!byOwner.has(owner)) byOwner.set(owner, []);
    byOwner.get(owner).push(doc);
  });
  let deleted = 0, kept = 0, skipped = 0;
  for (const [owner, docs] of byOwner) {
    if (docs.length < 2) { kept += docs.length; continue; }
    const flagged = docs.filter(d => d.data().isCheckInCircle === true);
    if (flagged.length === 0) { skipped += docs.length; console.log(`  ⚠️ ${owner}: ${docs.length} circles, none flagged — left alone`); continue; }
    for (const doc of docs) {
      const c = doc.data();
      const empty = (!Array.isArray(c.places) || c.places.length === 0) && !(c.placesCount > 0);
      if (c.isCheckInCircle === true || !empty) { kept++; continue; }
      // Belt and braces: verify no place docs point at it
      const linked = await db.collection('places').where('circleId', '==', doc.id).limit(1).get();
      if (!linked.empty) { kept++; console.log(`  ⚠️ ${owner}: ${doc.id} unflagged but has linked places — kept`); continue; }
      console.log(`  ${DRY_RUN ? 'would delete' : 'deleting'} empty duplicate ${doc.id} (owner ${owner})`);
      if (!DRY_RUN) await doc.ref.delete();
      deleted++;
    }
  }
  console.log(`${snap.size} "Check-in Places" circles, ${deleted} ${DRY_RUN ? 'would be ' : ''}deleted, ${kept} kept, ${skipped} skipped${DRY_RUN ? ' [DRY RUN]' : ''}`);
  process.exit(0);
})().catch(e => { console.error('❌', e); process.exit(1); });
