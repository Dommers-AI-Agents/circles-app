#!/usr/bin/env node

/**
 * Rollback migration script to revert 'myNetwork' privacy back to 'friends' in Firestore
 * Use this only if you need to rollback the network sharing feature
 */

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
const readline = require('readline');

async function rollbackFirestore() {
  try {
    // Initialize Firebase
    initializeFirebase();
    const db = getFirestore();
    
    console.log('🔥 Connected to Firestore');
    console.log('Project:', process.env.FIREBASE_PROJECT_ID || 'circles-app-83b67');
    console.log('---');

    // Rollback circles collection
    console.log('\n📂 Rolling back circles collection...');
    const circlesRef = db.collection('circles');
    const circlesSnapshot = await circlesRef.where('privacy', '==', 'myNetwork').get();
    
    let circleUpdateCount = 0;
    const circleBatch = db.batch();
    
    circlesSnapshot.forEach((doc) => {
      const docRef = circlesRef.doc(doc.id);
      circleBatch.update(docRef, { 
        privacy: 'friends',
        updatedAt: new Date().toISOString()
      });
      circleUpdateCount++;
    });
    
    if (circleUpdateCount > 0) {
      await circleBatch.commit();
      console.log(`✅ Reverted ${circleUpdateCount} circles from 'myNetwork' to 'friends' privacy`);
    } else {
      console.log('ℹ️  No circles found with "myNetwork" privacy');
    }

    // Note: We don't remove allowNetworkEdit field to preserve data integrity
    console.log('ℹ️  Note: allowNetworkEdit field preserved for data integrity');

    // Rollback places collection
    console.log('\n📂 Rolling back places collection...');
    const placesRef = db.collection('places');
    const placesSnapshot = await placesRef.where('privacy', '==', 'myNetwork').get();
    
    let placeUpdateCount = 0;
    const placeBatch = db.batch();
    
    placesSnapshot.forEach((doc) => {
      const docRef = placesRef.doc(doc.id);
      placeBatch.update(docRef, { 
        privacy: 'friends',
        updatedAt: new Date().toISOString()
      });
      placeUpdateCount++;
    });
    
    if (placeUpdateCount > 0) {
      await placeBatch.commit();
      console.log(`✅ Reverted ${placeUpdateCount} places from 'myNetwork' to 'friends' privacy`);
    } else {
      console.log('ℹ️  No places found with "myNetwork" privacy');
    }

    // Get summary statistics
    console.log('\n📊 Rollback Summary:');
    const totalCircles = await circlesRef.get();
    const friendsCircles = await circlesRef.where('privacy', '==', 'friends').get();
    const totalPlaces = await placesRef.get();
    const friendsPlaces = await placesRef.where('privacy', '==', 'friends').get();
    
    console.log(`Total circles: ${totalCircles.size} (${friendsCircles.size} with friends privacy)`);
    console.log(`Total places: ${totalPlaces.size} (${friendsPlaces.size} with friends privacy)`);

    // Check for any remaining 'myNetwork' privacy
    const remainingMyNetworkCircles = await circlesRef.where('privacy', '==', 'myNetwork').get();
    const remainingMyNetworkPlaces = await placesRef.where('privacy', '==', 'myNetwork').get();

    if (!remainingMyNetworkCircles.empty || !remainingMyNetworkPlaces.empty) {
      console.warn('\n⚠️  Warning: Some documents still have "myNetwork" privacy:');
      console.warn(`  - Circles: ${remainingMyNetworkCircles.size}`);
      console.warn(`  - Places: ${remainingMyNetworkPlaces.size}`);
    } else {
      console.log('\n✅ Rollback completed successfully!');
      console.log('All "myNetwork" privacy values have been reverted to "friends"');
    }

  } catch (error) {
    console.error('❌ Rollback failed:', error);
    process.exit(1);
  }
}

// Run rollback with confirmation
if (require.main === module) {
  console.log('🚀 Firestore Rollback: myNetwork -> friends');
  console.log('================================');
  
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  rl.question('\n⚠️  This will rollback the network sharing migration in Firestore. Are you sure? (yes/no): ', (answer) => {
    rl.close();
    
    if (answer.toLowerCase() === 'yes') {
      rollbackFirestore()
        .then(() => {
          console.log('\n✨ Rollback process complete!');
          process.exit(0);
        })
        .catch(err => {
          console.error(err);
          process.exit(1);
        });
    } else {
      console.log('Rollback cancelled.');
      process.exit(0);
    }
  });
}

module.exports = rollbackFirestore;