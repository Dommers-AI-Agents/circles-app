#!/usr/bin/env node

// Manually trigger daily summary for Brittany

require('dotenv').config();

// Initialize Firebase first
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const dailySummaryService = require('./services/dailySummaryService');
const db = getFirestore();

async function triggerSummaryForBrittany() {
  try {
    console.log('\n🚀 Manually triggering daily summary for Brittany...\n');
    
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
    const user = { id: userDoc.id, ...userDoc.data() };
    
    console.log(`✅ Found user: ${user.displayName} (${user.email})`);
    console.log(`🔔 Daily summary enabled: ${user.notificationPreferences?.dailySummary || false}`);
    console.log(`📱 Device tokens: ${user.deviceTokens?.length || 0}`);
    
    // Clear last daily summary to force send
    console.log('\n🧹 Clearing last daily summary timestamp...');
    await db.collection('users').doc(user.id).update({
      lastDailySummary: null
    });
    
    // Manually call the summary generation
    console.log('\n📊 Generating and sending summary...');
    await dailySummaryService.generateAndSendSummary(user);
    
    console.log('\n✅ Summary generation complete!');
    console.log('📱 Check Brittany\'s device for the notification');
    console.log('🔍 Ask Brittany to:');
    console.log('   1. Tap the notification when it arrives');
    console.log('   2. See if the full daily summary modal appears');
    console.log('   3. Report what happens');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

// Run the trigger
triggerSummaryForBrittany().then(() => {
  console.log('\n🎉 Done!');
  setTimeout(() => process.exit(0), 2000); // Give time for logs to flush
}).catch(error => {
  console.error('❌ Fatal error:', error);
  process.exit(1);
});