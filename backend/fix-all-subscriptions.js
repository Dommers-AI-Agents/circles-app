#!/usr/bin/env node

// Fix all subscription account issues found in the audit

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function fixAllSubscriptions() {
  console.log('🔧 Fixing all subscription account issues...\n');
  
  try {
    // Get all users with subscription status
    const usersSnapshot = await db.collection('users')
      .where('subscriptionStatus', 'in', ['active', 'trial', 'expired', 'cancelled'])
      .get();
    
    if (usersSnapshot.empty) {
      console.log('❌ No users with subscription status found');
      return;
    }
    
    console.log(`📊 Processing ${usersSnapshot.docs.length} users with subscription data\n`);
    
    let fixedCount = 0;
    const fixes = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const userUpdates = {};
      const quotaUpdates = {};
      let needsUserUpdate = false;
      let needsQuotaUpdate = false;
      
      console.log(`\n🔍 Processing: ${userData.displayName || 'Unknown'} (${userData.email})`);
      
      // Check expiry status
      let shouldBeExpired = false;
      if (userData.subscriptionExpiryDate) {
        const expiryDate = new Date(userData.subscriptionExpiryDate);
        shouldBeExpired = expiryDate < new Date();
      }
      
      // Fix subscription status if expired but marked as active/trial
      if ((userData.subscriptionStatus === 'active' || userData.subscriptionStatus === 'trial') && shouldBeExpired) {
        console.log(`   🔧 Updating status from "${userData.subscriptionStatus}" to "expired"`);
        userUpdates.subscriptionStatus = 'expired';
        needsUserUpdate = true;
      }
      
      // Add missing subscriptionTier for active/trial users
      if (!userData.subscriptionTier && (userData.subscriptionStatus === 'active' || userData.subscriptionStatus === 'trial')) {
        console.log(`   🔧 Adding missing subscriptionTier: "premium"`);
        userUpdates.subscriptionTier = 'premium';
        needsUserUpdate = true;
      }
      
      // Add missing platform
      if (!userData.subscriptionPlatform && (userData.subscriptionStatus === 'active' || userData.subscriptionStatus === 'trial')) {
        console.log(`   🔧 Adding missing subscriptionPlatform: "ios"`);
        userUpdates.subscriptionPlatform = 'ios';
        needsUserUpdate = true;
      }
      
      // Check quota document
      const quotaDoc = await db.collection('userVideoQuotas').doc(userId).get();
      if (quotaDoc.exists) {
        const quotaData = quotaDoc.data();
        const currentStatus = userUpdates.subscriptionStatus || userData.subscriptionStatus;
        const expectedQuotaTier = (currentStatus === 'active' || currentStatus === 'trial') ? 'premium' : 'free';
        
        if (quotaData.subscriptionTier !== expectedQuotaTier) {
          console.log(`   🔧 Updating quota tier from "${quotaData.subscriptionTier}" to "${expectedQuotaTier}"`);
          quotaUpdates.subscriptionTier = expectedQuotaTier;
          quotaUpdates.quotaLimit = expectedQuotaTier === 'free' ? 5 : 50;
          quotaUpdates.sizeLimit = expectedQuotaTier === 'free' ? 262144000 : 2147483648;
          quotaUpdates.updatedAt = new Date().toISOString();
          needsQuotaUpdate = true;
        }
      }
      
      // Apply fixes
      if (needsUserUpdate) {
        console.log(`   ✅ Updating user document`);
        await db.collection('users').doc(userId).update(userUpdates);
      }
      
      if (needsQuotaUpdate) {
        console.log(`   ✅ Updating quota document`);
        await db.collection('userVideoQuotas').doc(userId).update(quotaUpdates);
      }
      
      if (needsUserUpdate || needsQuotaUpdate) {
        fixedCount++;
        fixes.push({
          userId,
          email: userData.email,
          name: userData.displayName,
          userUpdates: needsUserUpdate ? userUpdates : null,
          quotaUpdates: needsQuotaUpdate ? quotaUpdates : null
        });
      } else {
        console.log(`   ✅ No fixes needed`);
      }
    }
    
    // Final summary
    console.log('\n' + '═'.repeat(80));
    console.log('FIX SUMMARY');
    console.log('═'.repeat(80));
    console.log(`Users processed: ${usersSnapshot.docs.length}`);
    console.log(`Users fixed: ${fixedCount}`);
    console.log(`Users already correct: ${usersSnapshot.docs.length - fixedCount}`);
    
    if (fixes.length > 0) {
      console.log('\n📝 Applied fixes:');
      fixes.forEach((fix, index) => {
        console.log(`\n${index + 1}. ${fix.name} (${fix.email})`);
        if (fix.userUpdates) {
          console.log(`   User updates: ${Object.keys(fix.userUpdates).join(', ')}`);
        }
        if (fix.quotaUpdates) {
          console.log(`   Quota updates: ${Object.keys(fix.quotaUpdates).join(', ')}`);
        }
      });
    }
    
    console.log('\n✅ All subscription accounts are now properly configured!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

fixAllSubscriptions().then(() => {
  console.log('\n🎉 All fixes complete!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});