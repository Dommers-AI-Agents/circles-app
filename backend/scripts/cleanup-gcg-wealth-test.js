// backend/scripts/cleanup-gcg-wealth-test.js
//
// "GCG Wealth Management, LLC" was only ever a test: one save in Wes's
// wesley@favcircles.com Charlotte circle, the canonical venue behind it, and
// an unclaimed store enrollment ("Wsley Test", test@favcircles.com). Wes
// asked for it gone everywhere (2026-09-27).
//
// Same cascade as cleanup-bogus-starbucks.js, plus the pieces that one didn't
// have to deal with:
//   - place save doc: soft-delete + pull from its circle + decrement
//     placesCount + browse-tree upkeep (what the deletePlace endpoint does)
//   - the "added a place" activity row: deleted, so the feed doesn't carry a
//     card pointing at a place that no longer exists
//   - globalPlaces doc: archived to deletedGlobalPlaces, then HARD deleted
//     (searchGlobalPlaces doesn't filter deletedAt, so a soft delete would
//     keep surfacing it under SUGGESTED NEARBY)
//   - stickerVenues enrollment: archived to deletedStickerVenues, then deleted
//   - the two photos he uploaded: removed from Storage, since nothing else
//     references them once the above are gone
//
// Refuses to touch anything it doesn't recognise, and stops if a second
// person turns out to have saved the venue. DRY_RUN=true to preview.
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore, admin } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { indexPlaceRemoved } = require('../services/circleLocationSummary');
const placeCache = require('../services/placeCache');
const DRY_RUN = process.env.DRY_RUN === 'true';

const SAVE_ID = 'KLFpHQJ3N7XLnpzTtYZA';
const GLOBAL_ID = 'rrnTAx4bEv9d0X9r5lAQ';
const VENUE_ID = 'Lw6JlJyoXBzCa8lOEVCZ';
const EXPECTED_NAME = 'GCG Wealth Management, LLC';
const BY = 'cleanup-gcg-wealth-test';

const say = (what) => console.log(`  ${DRY_RUN ? 'would ' : ''}${what}`);

/** The object path inside the bucket, from a Firebase download URL. */
const storagePathFromUrl = (url) => {
  const match = /\/o\/([^?]+)/.exec(url || '');
  return match ? decodeURIComponent(match[1]) : null;
};

(async () => {
  const now = new Date().toISOString();

  // --- the save ---
  const saveRef = db.collection('places').doc(SAVE_ID);
  const saveDoc = await saveRef.get();
  if (!saveDoc.exists) throw new Error(`save ${SAVE_ID} is gone already`);
  const save = saveDoc.data();
  if (save.name !== EXPECTED_NAME) throw new Error(`save ${SAVE_ID} is "${save.name}", not "${EXPECTED_NAME}" — refusing`);

  // Nobody else may be relying on this venue
  const linked = await db.collection('places').where('globalPlaceId', '==', GLOBAL_ID).get();
  const otherLive = linked.docs.filter(d => d.id !== SAVE_ID && !d.data().deletedAt);
  if (otherLive.length) {
    throw new Error(`${otherLive.length} other live save(s) reference this venue (${otherLive.map(d => d.id).join(', ')}) — refusing`);
  }

  if (save.deletedAt) {
    console.log(`save ${SAVE_ID} already soft-deleted at ${save.deletedAt}`);
  } else {
    say(`soft-delete save ${SAVE_ID} (circle ${save.circleId})`);
    if (!DRY_RUN) {
      const batch = db.batch();
      batch.update(saveRef, { deletedAt: now, updatedAt: now });
      const circleRef = db.collection('circles').doc(save.circleId);
      const circleDoc = await circleRef.get();
      if (circleDoc.exists) {
        const c = circleDoc.data();
        batch.update(circleRef, {
          places: (c.places || []).filter(id => id !== SAVE_ID),
          placesCount: Math.max(0, (c.placesCount || 0) - 1),
          updatedAt: now
        });
      }
      await batch.commit();
      indexPlaceRemoved(save.circleId, { ...save, id: SAVE_ID });
      placeCache.clear('browseTree', save.addedBy);
    }
  }

  // --- the feed card for it ---
  const activities = await db.collection('activities').where('targetId', '==', SAVE_ID).get();
  for (const doc of activities.docs) {
    say(`delete activity ${doc.id} (${doc.data().type})`);
    if (!DRY_RUN) await doc.ref.delete();
  }

  // --- the canonical venue ---
  const globalRef = db.collection('globalPlaces').doc(GLOBAL_ID);
  const globalDoc = await globalRef.get();
  if (!globalDoc.exists) {
    console.log(`globalPlace ${GLOBAL_ID} already gone`);
  } else if (globalDoc.data().name !== EXPECTED_NAME) {
    throw new Error(`globalPlace ${GLOBAL_ID} is "${globalDoc.data().name}" — refusing`);
  } else {
    say(`archive + delete globalPlace ${GLOBAL_ID}`);
    if (!DRY_RUN) {
      await db.collection('deletedGlobalPlaces').doc(GLOBAL_ID).set({ ...globalDoc.data(), deletedAt: now, deletedBy: BY });
      await globalRef.delete();
    }
  }

  // --- the unclaimed store enrollment ---
  const venueRef = db.collection('stickerVenues').doc(VENUE_ID);
  const venueDoc = await venueRef.get();
  if (!venueDoc.exists) {
    console.log(`stickerVenue ${VENUE_ID} already gone`);
  } else {
    const v = venueDoc.data();
    if (v.ownerId) throw new Error(`stickerVenue ${VENUE_ID} has been CLAIMED by ${v.ownerId} — refusing`);
    say(`archive + delete stickerVenue ${VENUE_ID} (${v.venueName}, contact ${v.contactEmail})`);
    if (!DRY_RUN) {
      await db.collection('deletedStickerVenues').doc(VENUE_ID).set({ ...v, deletedAt: now, deletedBy: BY });
      await venueRef.delete();
    }
  }

  // --- his two uploads ---
  const bucket = admin.storage().bucket();
  for (const url of save.photos || []) {
    const objectPath = storagePathFromUrl(url);
    if (!objectPath) { console.log(`  ⚠️ couldn't read an object path from ${url.slice(0, 80)}…`); continue; }
    say(`delete storage object ${objectPath}`);
    if (!DRY_RUN) await bucket.file(objectPath).delete().catch(e => console.log(`  ⚠️ ${objectPath}: ${e.message}`));
  }

  console.log(DRY_RUN ? '[DRY RUN] nothing was written' : '✅ GCG Wealth removed');
  process.exit(0);
})().catch(e => { console.error('❌', e.message); process.exit(1); });
