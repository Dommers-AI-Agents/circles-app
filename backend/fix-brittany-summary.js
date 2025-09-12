#!/usr/bin/env node

// Clear Brittany's lastDailySummary so she receives the next summary

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function fixBrittanySummary() {
  console.log('🔧 Fixing Brittany\'s daily summary issue\n');
  
  try {
    // Find Brittany
    const usersSnapshot = await db.collection('users')
      .where('email', '==', 'brittanyvans@gmail.com')
      .limit(1)
      .get();
    
    if (usersSnapshot.empty) {
      console.error('❌ Brittany not found');
      return;
    }
    
    const userDoc = usersSnapshot.docs[0];
    const userData = userDoc.data();
    const userId = userDoc.id;
    
    console.log(`✅ Found user: ${userData.displayName} (${userData.email})`);
    console.log(`   User ID: ${userId}`);
    console.log(`   Current lastDailySummary: ${userData.lastDailySummary || 'Not set'}`);
    
    if (userData.lastDailySummary) {
      const lastSummaryDate = new Date(userData.lastDailySummary);
      console.log(`   Last summary was: ${lastSummaryDate.toLocaleString()}`);
      
      // Clear the timestamp
      console.log('\n🧹 Clearing lastDailySummary timestamp...');
      await db.collection('users').doc(userId).update({
        lastDailySummary: null
      });
      console.log('✅ Timestamp cleared!');
      
      // Verify the update
      const updatedDoc = await db.collection('users').doc(userId).get();
      const updatedData = updatedDoc.data();
      console.log(`\n📋 Verification:`);
      console.log(`   lastDailySummary is now: ${updatedData.lastDailySummary || 'NULL (cleared)'}`);
      console.log(`   Daily summary enabled: ${updatedData.notificationPreferences?.dailySummary === true ? '✅ YES' : '❌ NO'}`);
      
      console.log('\n✅ Brittany will now receive the next daily summary!');
      console.log('   She should receive it at the next scheduled run.');
      console.log('   Or you can manually trigger it with: node trigger-brittany-summary.js');
    } else {
      console.log('ℹ️ lastDailySummary is already clear');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

fixBrittanySummary().then(() => {
  console.log('\n🎉 Done!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});