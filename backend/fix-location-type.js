// Repair: the fix-africa-places migration wrote location maps without type: 'Point',
// which breaks iOS Codable decoding (GeoLocation.type is non-optional) and blanks
// affected users' profiles. Restore the GeoJSON shape on every place missing it.
//
// Usage:
//   node fix-location-type.js           # dry run
//   node fix-location-type.js --apply   # write fixes

const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();

const APPLY = process.argv.includes('--apply');

async function main() {
  console.log(`🔍 Scanning places for location maps missing type... (${APPLY ? 'APPLY' : 'DRY RUN'})\n`);

  const snapshot = await db.collection('places').get();
  const broken = snapshot.docs.filter(doc => {
    const loc = doc.data().location;
    return loc && Array.isArray(loc.coordinates) && !loc.type;
  });

  if (broken.length === 0) {
    console.log('✅ All place location maps have a type field. Nothing to do.');
    return;
  }

  console.log(`Found ${broken.length} place(s) with location missing type:`);
  broken.forEach(doc => {
    const p = doc.data();
    console.log(`  ${doc.id}  "${p.name}"  coords=${JSON.stringify(p.location.coordinates)}  isSamplePlace=${p.isSamplePlace === true}`);
  });

  if (!APPLY) {
    console.log('\nDry run only. Re-run with --apply to set location.type = "Point".');
    return;
  }

  const batch = db.batch();
  broken.forEach(doc => {
    batch.update(doc.ref, {
      'location.type': 'Point',
      updatedAt: new Date().toISOString()
    });
  });
  await batch.commit();

  console.log(`\n✅ Set location.type = "Point" on ${broken.length} place(s).`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
