// backend/fix-africa-places.js
// One-off script: replace default/sample places stuck at coordinates [0, 0]
// (which render in the ocean off Africa) with the Starbucks in Belmar, NJ.
//
// Usage:
//   node fix-africa-places.js           # dry run - lists what would change
//   node fix-africa-places.js --apply   # actually update Firestore

const { initializeFirebase, getFirestore } = require('./config/firebase');

initializeFirebase();
const db = getFirestore();

const APPLY = process.argv.includes('--apply');

// Starbucks, Belmar NJ - coordinates stored as [longitude, latitude]
const BELMAR_STARBUCKS = {
  name: 'Starbucks',
  category: 'cafe',
  description: 'Popular coffee chain',
  address: '1799 River Rd, Belmar, NJ 07719',
  website: 'https://starbucks.com',
  // type: 'Point' is required - iOS GeoLocation decoding fails without it
  location: { type: 'Point', coordinates: [-74.0407, 40.1771] }
};

function isZeroZero(place) {
  const coords = place.location && place.location.coordinates;
  return Array.isArray(coords) && coords.length === 2 && coords[0] === 0 && coords[1] === 0;
}

async function fixAfricaPlaces() {
  console.log(`🔍 Scanning places for [0, 0] coordinates... (${APPLY ? 'APPLY' : 'DRY RUN'})\n`);

  const snapshot = await db.collection('places').get();
  const stuck = snapshot.docs.filter(doc => isZeroZero(doc.data()));

  if (stuck.length === 0) {
    console.log('✅ No places found at [0, 0]. Nothing to do.');
    return;
  }

  console.log(`Found ${stuck.length} place(s) at [0, 0]:\n`);

  let sampleCount = 0;
  for (const doc of stuck) {
    const place = doc.data();
    if (place.isSamplePlace) sampleCount++;
    console.log(`  ${doc.id}`);
    console.log(`    Name: ${place.name}`);
    console.log(`    Circle: ${place.circleId || 'N/A'}  Owner: ${place.addedBy || place.userId || 'N/A'}`);
    console.log(`    isSamplePlace: ${place.isSamplePlace === true}`);
    console.log('');
  }

  console.log(`${sampleCount} of ${stuck.length} are flagged isSamplePlace.\n`);

  if (!APPLY) {
    console.log('Dry run only. Re-run with --apply to replace these with the Belmar, NJ Starbucks.');
    return;
  }

  const batch = db.batch();
  for (const doc of stuck) {
    batch.update(doc.ref, {
      ...BELMAR_STARBUCKS,
      updatedAt: new Date().toISOString()
    });
  }
  await batch.commit();

  console.log(`✅ Updated ${stuck.length} place(s) to Starbucks, 1799 River Rd, Belmar, NJ.`);
}

fixAfricaPlaces()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Failed:', err);
    process.exit(1);
  });
