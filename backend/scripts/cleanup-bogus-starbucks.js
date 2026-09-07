// backend/scripts/cleanup-bogus-starbucks.js
// The curated onboarding list carried a "Starbucks, 1799 River Rd, Belmar,
// NJ 07719" entry that doesn't appear to be a real Starbucks, and the old
// wrong-city fallback seeded it to new users far outside NJ (e.g. Tucson).
// The entry is removed from data/popularPlaces.js; this script cleans up the
// copies already in Firestore:
//   - place save docs: soft-delete (deletedAt) + pull from their circle's
//     places[] + decrement placesCount — same cascade as the app's
//     deletePlace endpoint
//   - the canonical globalPlaces doc: archived to deletedGlobalPlaces, then
//     HARD deleted (searchGlobalPlaces doesn't filter deletedAt, so a soft
//     delete would keep surfacing it in SUGGESTED NEARBY)
// DRY_RUN=true to preview.
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const DRY_RUN = process.env.DRY_RUN === 'true';

const BOGUS_ADDRESS_FRAGMENT = '1799 river rd';

const isBogus = (data) =>
  (data.name || '').trim().toLowerCase() === 'starbucks' &&
  (data.address || '').toLowerCase().includes(BOGUS_ADDRESS_FRAGMENT);

(async () => {
  const now = new Date().toISOString();

  // --- place save docs ---
  const placeSnap = await db.collection('places').where('name', '==', 'Starbucks').get();
  const targets = placeSnap.docs.filter(d => isBogus(d.data()) && !d.data().deletedAt);
  console.log(`${placeSnap.size} "Starbucks" place docs, ${targets.length} match ${BOGUS_ADDRESS_FRAGMENT} and are live`);

  let softDeleted = 0;
  const globalPlaceIds = new Set();
  for (const doc of targets) {
    const p = doc.data();
    if (p.globalPlaceId) globalPlaceIds.add(p.globalPlaceId);
    const seeded = p.isSamplePlace === true ? 'sample-seeded' : 'NOT sample-flagged';
    console.log(`  ${DRY_RUN ? 'would soft-delete' : 'soft-deleting'} ${doc.id} (addedBy ${p.addedBy}, circle ${p.circleId}, ${seeded})`);
    if (!DRY_RUN) {
      const batch = db.batch();
      batch.update(doc.ref, { deletedAt: now, updatedAt: now });
      if (p.circleId) {
        const circleRef = db.collection('circles').doc(p.circleId);
        const circleDoc = await circleRef.get();
        if (circleDoc.exists) {
          const c = circleDoc.data();
          const places = (c.places || []).filter(id => id !== doc.id);
          batch.update(circleRef, {
            places,
            placesCount: Math.max(0, (c.placesCount || 0) - 1),
            updatedAt: now
          });
        }
      }
      await batch.commit();
    }
    softDeleted++;
  }

  // --- canonical globalPlaces docs ---
  // Linked ids from the save docs, plus a name query in case a canonical doc
  // exists with no live savers (that's exactly what SUGGESTED NEARBY shows).
  const globalSnap = await db.collection('globalPlaces').where('nameLower', '==', 'starbucks').get();
  globalSnap.docs.filter(d => isBogus(d.data())).forEach(d => globalPlaceIds.add(d.id));

  let removedGlobal = 0;
  for (const id of globalPlaceIds) {
    const ref = db.collection('globalPlaces').doc(id);
    const doc = await ref.get();
    if (!doc.exists) continue;
    const g = doc.data();
    if (!isBogus(g)) { console.log(`  ⚠️ globalPlace ${id} linked but doesn't match — left alone (${g.name} / ${g.address})`); continue; }
    // Belt and braces: no OTHER live save doc may still reference this venue
    const stillLinked = await db.collection('places')
      .where('globalPlaceId', '==', id).get();
    const liveOthers = stillLinked.docs.filter(d => !d.data().deletedAt && !targets.some(t => t.id === d.id));
    if (liveOthers.length > 0 && !DRY_RUN) {
      console.log(`  ⚠️ globalPlace ${id} still referenced by ${liveOthers.length} live saves — left alone`);
      continue;
    }
    console.log(`  ${DRY_RUN ? 'would remove' : 'removing'} globalPlace ${id} (${g.name}, ${g.address})`);
    if (!DRY_RUN) {
      // Convention: archive before removing
      await db.collection('deletedGlobalPlaces').doc(id).set({ ...g, deletedAt: now, deletedBy: 'cleanup-bogus-starbucks' });
      await ref.delete();
    }
    removedGlobal++;
  }

  console.log(`${softDeleted} save docs ${DRY_RUN ? 'would be ' : ''}soft-deleted, ${removedGlobal} globalPlaces ${DRY_RUN ? 'would be ' : ''}removed${DRY_RUN ? ' [DRY RUN]' : ''}`);
  process.exit(0);
})().catch(e => { console.error('❌', e); process.exit(1); });
