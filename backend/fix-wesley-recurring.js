#!/usr/bin/env node

// Fix Wesley's account - he has recurring subscription, not expired

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function fixWesleyRecurring() {
  console.log('🔧 Fixing Wesley\'s recurring subscription status...\n');
  
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
    const userId = userDoc.id;
    
    console.log('Wesley has recurring $2.99/month subscription that renews until cancelled');
    console.log('The expiry date shown is the NEXT RENEWAL DATE, not when access ends\n');
    
    // Fix user document - set as active recurring subscription
    const userUpdates = {
      subscriptionStatus: 'active',  // Active recurring subscription
      subscriptionTier: 'premium',
      subscriptionPlatform: 'ios',
      // Update to next renewal date (monthly)
      subscriptionExpiryDate: '2025-09-22T10:11:49.000Z' // Next month renewal
    };
    
    console.log('Updating Wesley\'s user document:');
    console.log(`   subscriptionStatus: ${userUpdates.subscriptionStatus}`);
    console.log(`   subscriptionTier: ${userUpdates.subscriptionTier}`);
    console.log(`   Next renewal: ${new Date(userUpdates.subscriptionExpiryDate).toLocaleDateString()}`);
    
    await db.collection('users').doc(userId).update(userUpdates);
    console.log('✅ User document updated');
    
    // Fix quota document - set to premium
    const quotaRef = db.collection('userVideoQuotas').doc(userId);
    const quotaUpdates = {
      subscriptionTier: 'premium',
      quotaLimit: 50, // Premium limit
      sizeLimit: 2147483648, // 2GB for premium
      updatedAt: new Date().toISOString()
    };
    
    console.log('\nUpdating Wesley\'s quota document:');
    console.log(`   subscriptionTier: ${quotaUpdates.subscriptionTier}`);
    console.log(`   quotaLimit: ${quotaUpdates.quotaLimit} videos/month`);
    
    await quotaRef.update(quotaUpdates);
    console.log('✅ Quota document updated');
    
    console.log('\n✅ Wesley\'s recurring subscription is now properly configured!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

fixWesleyRecurring().then(() => {
  console.log('\n🎉 Done!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});