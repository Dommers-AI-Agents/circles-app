#!/usr/bin/env node

/**
 * Migration script to update 'friends' privacy to 'myNetwork' in Firestore
 * Run this to migrate the production Firestore database
 */

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');

async function migrateFirestore() {
  try {
    // Initialize Firebase
    initializeFirebase();
    const db = getFirestore();
    
    console.log('🔥 Connected to Firestore');
    console.log('Project:', process.env.FIREBASE_PROJECT_ID || 'circles-app-83b67');
    console.log('---');

    // Migrate circles collection
    console.log('\n📂 Migrating circles collection...');
    const circlesRef = db.collection('circles');
    const circlesSnapshot = await circlesRef.where('privacy', '==', 'friends').get();
    
    let circleUpdateCount = 0;
    const circleBatch = db.batch();
    
    circlesSnapshot.forEach((doc) => {
      const docRef = circlesRef.doc(doc.id);
      circleBatch.update(docRef, { 
        privacy: 'myNetwork',
        updatedAt: new Date().toISOString()
      });
      circleUpdateCount++;
    });
    
    if (circleUpdateCount > 0) {
      await circleBatch.commit();
      console.log(`✅ Updated ${circleUpdateCount} circles from 'friends' to 'myNetwork' privacy`);
    } else {
      console.log('ℹ️  No circles found with "friends" privacy');
    }

    // Add allowNetworkEdit field to circles that don't have it
    console.log('\n📝 Adding allowNetworkEdit field to circles...');
    const allCirclesSnapshot = await circlesRef.get();
    let fieldAddCount = 0;
    const fieldBatch = db.batch();
    
    for (const doc of allCirclesSnapshot.docs) {
      const data = doc.data();
      if (data.allowNetworkEdit === undefined) {
        const docRef = circlesRef.doc(doc.id);
        fieldBatch.update(docRef, { 
          allowNetworkEdit: false,
          updatedAt: new Date().toISOString()
        });
        fieldAddCount++;
        
        // Firestore has a limit of 500 operations per batch
        if (fieldAddCount % 500 === 0) {
          await fieldBatch.commit();
          console.log(`  Processed ${fieldAddCount} circles...`);
        }
      }
    }
    
    if (fieldAddCount % 500 !== 0 && fieldAddCount > 0) {
      await fieldBatch.commit();
    }
    
    console.log(`✅ Added allowNetworkEdit field to ${fieldAddCount} circles`);

    // Migrate places collection
    console.log('\n📂 Migrating places collection...');
    const placesRef = db.collection('places');
    const placesSnapshot = await placesRef.where('privacy', '==', 'friends').get();
    
    let placeUpdateCount = 0;
    const placeBatch = db.batch();
    
    placesSnapshot.forEach((doc) => {
      const docRef = placesRef.doc(doc.id);
      placeBatch.update(docRef, { 
        privacy: 'myNetwork',
        updatedAt: new Date().toISOString()
      });
      placeUpdateCount++;
    });
    
    if (placeUpdateCount > 0) {
      await placeBatch.commit();
      console.log(`✅ Updated ${placeUpdateCount} places from 'friends' to 'myNetwork' privacy`);
    } else {
      console.log('ℹ️  No places found with "friends" privacy');
    }

    // Get summary statistics
    console.log('\n📊 Migration Summary:');
    const totalCircles = await circlesRef.get();
    const myNetworkCircles = await circlesRef.where('privacy', '==', 'myNetwork').get();
    const totalPlaces = await placesRef.get();
    const myNetworkPlaces = await placesRef.where('privacy', '==', 'myNetwork').get();
    
    console.log(`Total circles: ${totalCircles.size} (${myNetworkCircles.size} with myNetwork privacy)`);
    console.log(`Total places: ${totalPlaces.size} (${myNetworkPlaces.size} with myNetwork privacy)`);

    // Check for any remaining 'friends' privacy
    const remainingFriendsCircles = await circlesRef.where('privacy', '==', 'friends').get();
    const remainingFriendsPlaces = await placesRef.where('privacy', '==', 'friends').get();

    if (!remainingFriendsCircles.empty || !remainingFriendsPlaces.empty) {
      console.warn('\n⚠️  Warning: Some documents still have "friends" privacy:');
      console.warn(`  - Circles: ${remainingFriendsCircles.size}`);
      console.warn(`  - Places: ${remainingFriendsPlaces.size}`);
    } else {
      console.log('\n✅ Migration completed successfully!');
      console.log('All "friends" privacy values have been updated to "myNetwork"');
    }

  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

// Run migration
if (require.main === module) {
  console.log('🚀 Starting Firestore migration: friends -> myNetwork');
  console.log('================================');
  
  migrateFirestore()
    .then(() => {
      console.log('\n✨ Migration process complete!');
      process.exit(0);
    })
    .catch(err => {
      console.error(err);
      process.exit(1);
    });
}

module.exports = migrateFirestore;