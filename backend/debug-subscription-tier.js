#!/usr/bin/env node

// Debug what getUserSubscriptionTier returns for Wesley

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const videoQuotaService = require('./services/videoQuotaService');

async function debugSubscriptionTier() {
  console.log('🔍 Debugging subscription tier detection for Wesley\n');
  
  try {
    // Find Wesley's user ID
    const db = getFirestore();
    const usersSnapshot = await db.collection('users')
      .where('email', '==', 'sgroiwes@gmail.com')
      .limit(1)
      .get();
    
    if (usersSnapshot.empty) {
      console.error('❌ Wesley not found');
      return;
    }
    
    const userDoc = usersSnapshot.docs[0];
    const userData = userDoc.data();
    const userId = userDoc.id;
    
    console.log('═'.repeat(60));
    console.log('USER DATA');
    console.log('═'.repeat(60));
    console.log(`User: ${userData.displayName} (${userData.email})`);
    console.log(`User ID: ${userId}\n`);
    
    console.log('Subscription fields:');
    console.log(`   subscriptionStatus: "${userData.subscriptionStatus || 'NOT SET'}"`);
    console.log(`   subscriptionTier: "${userData.subscriptionTier || 'NOT SET'}"`);
    console.log(`   subscriptionPlatform: "${userData.subscriptionPlatform || 'NOT SET'}"`);
    
    if (userData.subscriptionExpiryDate) {
      const expiryDate = new Date(userData.subscriptionExpiryDate);
      const isExpired = expiryDate < new Date();
      console.log(`   subscriptionExpiryDate: "${userData.subscriptionExpiryDate}"`);
      console.log(`   Parsed expiry: ${expiryDate.toLocaleString()}`);
      console.log(`   Is expired: ${isExpired ? '❌ YES' : '✅ NO'}`);
    } else {
      console.log(`   subscriptionExpiryDate: NOT SET`);
    }
    
    // Test the getUserSubscriptionTier function
    console.log('\n═'.repeat(60));
    console.log('SUBSCRIPTION TIER DETECTION');
    console.log('═'.repeat(60));
    
    const detectedTier = await videoQuotaService.getUserSubscriptionTier(userId);
    console.log(`\n🎯 VideoQuotaService.getUserSubscriptionTier() returned: "${detectedTier}"`);
    
    // Manual check of the logic
    console.log('\n🔍 Manual logic check:');
    console.log(`   1. subscriptionStatus check:`);
    console.log(`      Is "active"? ${userData.subscriptionStatus === 'active' ? '✅ YES' : '❌ NO'}`);
    console.log(`      Is "trial"? ${userData.subscriptionStatus === 'trial' ? '✅ YES' : '❌ NO'}`);
    console.log(`      Either active or trial? ${(userData.subscriptionStatus === 'active' || userData.subscriptionStatus === 'trial') ? '✅ YES' : '❌ NO'}`);
    
    if (userData.subscriptionStatus === 'active' || userData.subscriptionStatus === 'trial') {
      console.log(`\n   2. Expiry date check:`);
      if (userData.subscriptionExpiryDate) {
        const expiryDate = new Date(userData.subscriptionExpiryDate);
        const now = new Date();
        console.log(`      Has expiry date: ✅ YES`);
        console.log(`      Expiry: ${expiryDate.toISOString()}`);
        console.log(`      Now: ${now.toISOString()}`);
        console.log(`      Is valid (expiry > now)? ${expiryDate > now ? '✅ YES' : '❌ NO'}`);
        console.log(`      → Result: ${expiryDate > now ? 'PREMIUM' : 'FREE'}`);
      } else {
        console.log(`      Has expiry date: ❌ NO`);
        console.log(`      → Result: PREMIUM (no expiry = active)`);
      }
    } else {
      console.log(`\n   → Result: FREE (status not active/trial)`);
    }
    
    // Check what quota would be created
    console.log('\n═'.repeat(60));
    console.log('QUOTA CREATION TEST');
    console.log('═'.repeat(60));
    
    const testQuota = await videoQuotaService.getUserQuota(userId);
    console.log(`Quota object subscription tier: "${testQuota.subscriptionTier}"`);
    console.log(`Quota limit: ${testQuota.quotaLimit} videos/month`);
    console.log(`Videos uploaded: ${testQuota.videosUploaded}`);
    console.log(`Can upload: ${testQuota.videosUploaded < testQuota.quotaLimit ? '✅ YES' : '❌ NO'}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

debugSubscriptionTier().then(() => {
  console.log('\n✅ Debug complete!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});