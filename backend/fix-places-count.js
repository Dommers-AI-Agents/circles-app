#!/usr/bin/env node

/**
 * Script to fix placesCount for all circles
 * This recalculates the actual number of non-deleted places in each circle
 * and updates the placesCount field accordingly
 * 
 * Run with: node fix-places-count.js
 */

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function fixPlacesCount() {
  try {
    console.log('🔧 Starting to fix placesCount for all circles...\n');
    
    // Get all circles
    const circlesSnapshot = await db.collection('circles').get();
    console.log(`📊 Found ${circlesSnapshot.size} total circles to process\n`);
    
    let totalFixed = 0;
    let totalCorrect = 0;
    let systemCirclesFixed = 0;
    
    // Process each circle
    for (const circleDoc of circlesSnapshot.docs) {
      const circle = circleDoc.data();
      const circleId = circleDoc.id;
      
      // Get the actual count of non-deleted places in this circle
      const placesSnapshot = await db.collection('places')
        .where('circleId', '==', circleId)
        .where('deletedAt', '==', null)
        .get();
      
      const actualPlaceCount = placesSnapshot.size;
      const currentPlaceCount = circle.placesCount || 0;
      const placesArrayLength = circle.places ? circle.places.length : 0;
      
      // Check if the count needs to be fixed
      if (currentPlaceCount !== actualPlaceCount) {
        // Update the placesCount
        await db.collection('circles').doc(circleId).update({
          placesCount: actualPlaceCount,
          updatedAt: new Date().toISOString()
        });
        
        console.log(`✅ Fixed "${circle.name}" (${circleId})`);
        console.log(`   Owner: ${circle.owner}`);
        console.log(`   Old placesCount: ${currentPlaceCount}`);
        console.log(`   New placesCount: ${actualPlaceCount}`);
        console.log(`   Places array length: ${placesArrayLength}`);
        
        if (circle.isSystemCircle) {
          console.log(`   🤖 System circle: ${circle.name}`);
          systemCirclesFixed++;
        }
        
        console.log('');
        totalFixed++;
      } else {
        totalCorrect++;
      }
    }
    
    console.log('\n📈 Summary:');
    console.log(`✅ Fixed: ${totalFixed} circles`);
    console.log(`✓ Already correct: ${totalCorrect} circles`);
    console.log(`🤖 System circles fixed: ${systemCirclesFixed}`);
    console.log(`📊 Total processed: ${circlesSnapshot.size} circles`);
    
    // Special check for sgroiwes@gmail.com's system circles
    console.log('\n🔍 Checking sgroiwes@gmail.com system circles...');
    
    // Find the user
    const userSnapshot = await db.collection('users')
      .where('email', '==', 'sgroiwes@gmail.com')
      .limit(1)
      .get();
    
    if (!userSnapshot.empty) {
      const userId = userSnapshot.docs[0].id;
      console.log(`Found user: ${userId}`);
      
      // Check their system circles
      const systemCirclesSnapshot = await db.collection('circles')
        .where('owner', '==', userId)
        .where('isSystemCircle', '==', true)
        .get();
      
      console.log(`\nSystem circles for sgroiwes@gmail.com:`);
      for (const doc of systemCirclesSnapshot.docs) {
        const circle = doc.data();
        console.log(`  - ${circle.name}: ${circle.placesCount} places`);
      }
    } else {
      console.log('User sgroiwes@gmail.com not found');
    }
    
    console.log('\n✨ Fix completed successfully!');
    
  } catch (error) {
    console.error('❌ Error fixing places count:', error);
    process.exit(1);
  }
}

// Run the fix
fixPlacesCount()
  .then(() => {
    console.log('\n👋 Exiting...');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Fatal error:', error);
    process.exit(1);
  });