#!/usr/bin/env node

// Fix Wesley's subscription status and video quota

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function fixWesleySubscription() {
  console.log('🔧 Fixing Wesley\'s subscription status and video quota\n');
  
  try {
    // Find Wesley
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
    console.log('CURRENT STATUS');
    console.log('═'.repeat(60));
    console.log(`User: ${userData.displayName} (${userData.email})`);
    console.log(`User ID: ${userId}`);
    console.log(`\nCurrent subscription status: ${userData.subscriptionStatus || 'NOT SET'}`);
    console.log(`Current subscription tier: ${userData.subscriptionTier || 'NOT SET'}`);
    console.log(`Expiry date: ${userData.subscriptionExpiryDate || 'NOT SET'}`);
    
    // Fix user subscription status
    console.log('\n' + '═'.repeat(60));
    console.log('FIXING USER DOCUMENT');
    console.log('═'.repeat(60));
    
    const userUpdates = {
      subscriptionStatus: 'active',
      subscriptionTier: 'premium',
      subscriptionPlatform: 'ios',
      // Keep the existing expiry date (Aug 22, 2025)
      subscriptionExpiryDate: userData.subscriptionExpiryDate || '2025-08-22T10:11:49.000Z'
    };
    
    console.log('Updating user document with:');
    console.log(`   subscriptionStatus: ${userUpdates.subscriptionStatus}`);
    console.log(`   subscriptionTier: ${userUpdates.subscriptionTier}`);
    console.log(`   subscriptionPlatform: ${userUpdates.subscriptionPlatform}`);
    console.log(`   subscriptionExpiryDate: ${userUpdates.subscriptionExpiryDate}`);
    
    await db.collection('users').doc(userId).update(userUpdates);
    console.log('✅ User document updated');
    
    // Fix video quota document
    console.log('\n' + '═'.repeat(60));
    console.log('FIXING VIDEO QUOTA');
    console.log('═'.repeat(60));
    
    const quotaRef = db.collection('userVideoQuotas').doc(userId);
    const quotaDoc = await quotaRef.get();
    
    if (!quotaDoc.exists) {
      console.log('Creating new premium quota document...');
      const now = new Date();
      const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      
      const newQuota = {
        userId: userId,
        currentMonth: currentMonth,
        videosUploaded: 0,
        totalSize: 0,
        subscriptionTier: 'premium',
        quotaLimit: 50, // Premium limit
        sizeLimit: 2147483648, // 2GB for premium
        lastResetDate: now.toISOString(),
        createdAt: now.toISOString(),
        updatedAt: now.toISOString()
      };
      
      await quotaRef.set(newQuota);
      console.log('✅ Created new premium quota document');
    } else {
      const quotaData = quotaDoc.data();
      console.log(`Current quota: ${quotaData.videosUploaded}/${quotaData.quotaLimit} videos`);
      console.log(`Current tier: ${quotaData.subscriptionTier}`);
      
      // Update to premium tier
      const quotaUpdates = {
        subscriptionTier: 'premium',
        quotaLimit: 50, // Premium gets 50 videos/month
        sizeLimit: 2147483648, // 2GB for premium
        updatedAt: new Date().toISOString()
      };
      
      console.log('\nUpdating quota document with:');
      console.log(`   subscriptionTier: ${quotaUpdates.subscriptionTier}`);
      console.log(`   quotaLimit: ${quotaUpdates.quotaLimit} videos/month`);
      console.log(`   sizeLimit: ${(quotaUpdates.sizeLimit / 1024 / 1024 / 1024).toFixed(2)} GB`);
      
      await quotaRef.update(quotaUpdates);
      console.log('✅ Quota document updated');
      
      // Show new status
      console.log(`\n📊 New quota status:`);
      console.log(`   Videos uploaded this month: ${quotaData.videosUploaded}`);
      console.log(`   New limit: ${quotaUpdates.quotaLimit}`);
      console.log(`   Remaining: ${quotaUpdates.quotaLimit - quotaData.videosUploaded} videos`);
      console.log(`   Can upload now: ${quotaData.videosUploaded < quotaUpdates.quotaLimit ? '✅ YES' : '❌ NO'}`);
    }
    
    // Verify the fix
    console.log('\n' + '═'.repeat(60));
    console.log('VERIFICATION');
    console.log('═'.repeat(60));
    
    // Re-fetch documents to verify
    const verifyUserDoc = await db.collection('users').doc(userId).get();
    const verifyUserData = verifyUserDoc.data();
    const verifyQuotaDoc = await quotaRef.get();
    const verifyQuotaData = verifyQuotaDoc.data();
    
    console.log('User document:');
    console.log(`   subscriptionStatus: ${verifyUserData.subscriptionStatus} ${verifyUserData.subscriptionStatus === 'active' ? '✅' : '❌'}`);
    console.log(`   subscriptionTier: ${verifyUserData.subscriptionTier} ${verifyUserData.subscriptionTier === 'premium' ? '✅' : '❌'}`);
    
    console.log('\nQuota document:');
    console.log(`   subscriptionTier: ${verifyQuotaData.subscriptionTier} ${verifyQuotaData.subscriptionTier === 'premium' ? '✅' : '❌'}`);
    console.log(`   quotaLimit: ${verifyQuotaData.quotaLimit} ${verifyQuotaData.quotaLimit === 50 ? '✅' : '❌'}`);
    console.log(`   Can upload: ${verifyQuotaData.videosUploaded < verifyQuotaData.quotaLimit ? '✅ YES' : '❌ NO'}`);
    
    console.log('\n✅ Fix complete! You should now be able to upload moments as a premium user.');
    console.log('   Try uploading a moment again in the app.');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

fixWesleySubscription().then(() => {
  console.log('\n🎉 Done!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});