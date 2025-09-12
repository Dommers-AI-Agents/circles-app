#!/usr/bin/env node

// List all subscribed users with their details

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();

const db = getFirestore();

async function listSubscribedUsers() {
  console.log('📋 Listing all subscribed users...\n');
  
  try {
    // Find all users with active subscription status
    const usersSnapshot = await db.collection('users')
      .where('subscriptionStatus', 'in', ['active', 'trial'])
      .get();
    
    if (usersSnapshot.empty) {
      console.log('❌ No subscribed users found');
      return;
    }
    
    console.log(`📊 Found ${usersSnapshot.docs.length} subscribed users\n`);
    console.log('═'.repeat(80));
    console.log('SUBSCRIBED USERS LIST');
    console.log('═'.repeat(80));
    
    const activeUsers = [];
    const trialUsers = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      const userInfo = {
        name: userData.displayName || 'Unknown',
        email: userData.email || 'No email',
        userId: userId,
        status: userData.subscriptionStatus,
        tier: userData.subscriptionTier,
        platform: userData.subscriptionPlatform,
        expiryDate: userData.subscriptionExpiryDate
      };
      
      if (userData.subscriptionStatus === 'active') {
        activeUsers.push(userInfo);
      } else if (userData.subscriptionStatus === 'trial') {
        trialUsers.push(userInfo);
      }
    }
    
    // Display active subscriptions
    if (activeUsers.length > 0) {
      console.log(`\n🟢 ACTIVE SUBSCRIPTIONS (${activeUsers.length}):`);
      activeUsers.forEach((user, index) => {
        console.log(`\n${index + 1}. ${user.name}`);
        console.log(`   Email: ${user.email}`);
        console.log(`   Status: ${user.status} (recurring)`);
        console.log(`   Tier: ${user.tier}`);
        if (user.expiryDate) {
          const renewalDate = new Date(user.expiryDate);
          console.log(`   Next renewal: ${renewalDate.toLocaleDateString()}`);
        }
      });
    }
    
    // Display trial subscriptions
    if (trialUsers.length > 0) {
      console.log(`\n🟡 TRIAL SUBSCRIPTIONS (${trialUsers.length}):`);
      trialUsers.forEach((user, index) => {
        console.log(`\n${index + 1}. ${user.name}`);
        console.log(`   Email: ${user.email}`);
        console.log(`   Status: ${user.status} (free trial)`);
        console.log(`   Tier: ${user.tier}`);
        if (user.expiryDate) {
          const expiryDate = new Date(user.expiryDate);
          const daysLeft = Math.ceil((expiryDate - new Date()) / (1000 * 60 * 60 * 24));
          console.log(`   Trial expires: ${expiryDate.toLocaleDateString()} (${daysLeft} days left)`);
        }
      });
    }
    
    // Summary
    console.log('\n' + '═'.repeat(80));
    console.log('SUMMARY');
    console.log('═'.repeat(80));
    console.log(`Total subscribed users: ${usersSnapshot.docs.length}`);
    console.log(`Active subscriptions: ${activeUsers.length}`);
    console.log(`Trial subscriptions: ${trialUsers.length}`);
    
    // Calculate potential revenue
    const monthlyRevenue = activeUsers.length * 2.99;
    console.log(`\nEstimated monthly revenue: $${monthlyRevenue.toFixed(2)}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

listSubscribedUsers().then(() => {
  console.log('\n✅ List complete!');
  process.exit(0);
}).catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});