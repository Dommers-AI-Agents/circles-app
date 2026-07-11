// One-off: re-point the 'test' user's onboarding sample place to a real place
// near their registration zipcode, using the new PlaceDiscoveryService.
//
// Usage:
//   node fix-test-user-sample-place.js           # dry run
//   node fix-test-user-sample-place.js --apply   # write the fix

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();

const PlaceDiscoveryService = require('./services/placeDiscoveryService');

const APPLY = process.argv.includes('--apply');

async function main() {
  // Find the user named 'test' (most recent if several)
  const usersSnap = await db.collection('users').get();
  const testUsers = usersSnap.docs
    .filter(d => (d.data().displayName || '').toLowerCase() === 'test')
    .sort((a, b) => (b.data().createdAt || '').localeCompare(a.data().createdAt || ''));

  if (testUsers.length === 0) {
    console.log('No user with displayName "test" found.');
    return;
  }

  const userDoc = testUsers[0];
  const user = userDoc.data();
  console.log(`User: ${user.displayName} <${user.email}> [${userDoc.id}]`);
  console.log(`  zipcode: ${user.zipcode || '-'}  location: ${user.location || '-'}  createdAt: ${user.createdAt}`);

  // Find their sample place
  const placesSnap = await db.collection('places')
    .where('addedBy', '==', userDoc.id)
    .get();
  const samplePlaces = placesSnap.docs.filter(d => d.data().isSamplePlace === true);

  if (samplePlaces.length === 0) {
    console.log('No sample place found for this user.');
    return;
  }
  const sampleDoc = samplePlaces[0];
  const sample = sampleDoc.data();
  console.log(`\nCurrent sample place: "${sample.name}" @ ${sample.address}`);

  if (!user.zipcode && !user.lastKnownLocation) {
    console.log('User has no zipcode or coordinates - cannot localize. Nothing to do.');
    return;
  }

  const city = (user.location || '').split(',')[0].trim() || null;
  const nearby = await PlaceDiscoveryService.findNearbyPlace({
    zipcode: user.zipcode,
    coordinates: user.lastKnownLocation,
    city
  });

  if (!nearby) {
    console.log('Nearby search returned nothing - leaving sample place unchanged.');
    return;
  }

  console.log(`\nReplacement: "${nearby.name}" @ ${nearby.address}`);
  console.log(`  category: ${nearby.category}  rating: ${nearby.rating}  coords: ${JSON.stringify(nearby.coordinates)}`);

  if (!APPLY) {
    console.log('\nDry run only. Re-run with --apply to update the sample place.');
    return;
  }

  await sampleDoc.ref.update({
    name: nearby.name,
    description: nearby.description,
    address: nearby.address,
    category: nearby.category,
    rating: nearby.rating,
    googlePlaceId: nearby.googlePlaceId,
    website: null,
    location: { type: 'Point', coordinates: nearby.coordinates },
    updatedAt: new Date().toISOString()
  });
  console.log(`\n✅ Updated sample place ${sampleDoc.id} to "${nearby.name}".`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
