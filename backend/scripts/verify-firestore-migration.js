#!/usr/bin/env node

/**
 * Verification script to check the Firestore migration status
 */

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');

async function verifyMigration() {
  try {
    // Initialize Firebase
    initializeFirebase();
    const db = getFirestore();
    
    console.log('🔍 Verifying Firestore Migration Status');
    console.log('=====================================');

    // Check circles
    const circlesRef = db.collection('circles');
    const allCircles = await circlesRef.get();
    const publicCircles = await circlesRef.where('privacy', '==', 'public').get();
    const myNetworkCircles = await circlesRef.where('privacy', '==', 'myNetwork').get();
    const privateCircles = await circlesRef.where('privacy', '==', 'private').get();
    const friendsCircles = await circlesRef.where('privacy', '==', 'friends').get();
    
    console.log('\n📊 Circles Collection:');
    console.log(`Total circles: ${allCircles.size}`);
    console.log(`- Public: ${publicCircles.size}`);
    console.log(`- My Network: ${myNetworkCircles.size}`);
    console.log(`- Private: ${privateCircles.size}`);
    console.log(`- Friends (old): ${friendsCircles.size}`);

    // Check allowNetworkEdit field
    let circlesWithAllowEdit = 0;
    let circlesWithoutAllowEdit = 0;
    
    allCircles.forEach(doc => {
      const data = doc.data();
      if (data.allowNetworkEdit !== undefined) {
        circlesWithAllowEdit++;
      } else {
        circlesWithoutAllowEdit++;
      }
    });
    
    console.log(`\n📝 allowNetworkEdit field:`);
    console.log(`- Circles with field: ${circlesWithAllowEdit}`);
    console.log(`- Circles without field: ${circlesWithoutAllowEdit}`);

    // Check places
    const placesRef = db.collection('places');
    const allPlaces = await placesRef.get();
    const publicPlaces = await placesRef.where('privacy', '==', 'public').get();
    const myNetworkPlaces = await placesRef.where('privacy', '==', 'myNetwork').get();
    const privatePlaces = await placesRef.where('privacy', '==', 'private').get();
    const followCirclePlaces = await placesRef.where('privacy', '==', 'followCircle').get();
    const friendsPlaces = await placesRef.where('privacy', '==', 'friends').get();
    
    console.log('\n📊 Places Collection:');
    console.log(`Total places: ${allPlaces.size}`);
    console.log(`- Follow Circle: ${followCirclePlaces.size}`);
    console.log(`- Public: ${publicPlaces.size}`);
    console.log(`- My Network: ${myNetworkPlaces.size}`);
    console.log(`- Private: ${privatePlaces.size}`);
    console.log(`- Friends (old): ${friendsPlaces.size}`);

    // Sample a few circles to show details
    console.log('\n📋 Sample Circles (first 3):');
    let count = 0;
    for (const doc of allCircles.docs) {
      if (count >= 3) break;
      const data = doc.data();
      console.log(`\nCircle: ${data.name}`);
      console.log(`  ID: ${doc.id}`);
      console.log(`  Privacy: ${data.privacy}`);
      console.log(`  Allow Network Edit: ${data.allowNetworkEdit}`);
      console.log(`  Owner: ${data.owner}`);
      count++;
    }

    // Check migration status
    console.log('\n✅ Migration Status:');
    if (friendsCircles.size === 0 && friendsPlaces.size === 0) {
      console.log('✓ All "friends" privacy values have been migrated to "myNetwork"');
    } else {
      console.log('⚠️  Some documents still have "friends" privacy!');
    }
    
    if (circlesWithoutAllowEdit === 0) {
      console.log('✓ All circles have the allowNetworkEdit field');
    } else {
      console.log(`⚠️  ${circlesWithoutAllowEdit} circles are missing the allowNetworkEdit field`);
    }

  } catch (error) {
    console.error('❌ Verification failed:', error);
    process.exit(1);
  }
}

// Run verification
if (require.main === module) {
  verifyMigration()
    .then(() => {
      console.log('\n✨ Verification complete!');
      process.exit(0);
    })
    .catch(err => {
      console.error(err);
      process.exit(1);
    });
}

module.exports = verifyMigration;