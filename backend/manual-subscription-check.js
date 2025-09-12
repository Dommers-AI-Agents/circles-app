#!/usr/bin/env node

/**
 * Manual subscription verification script for users whose iOS app
 * failed to send subscription data to the backend
 * 
 * This script helps diagnose subscription issues by:
 * 1. Checking if user exists and their current status
 * 2. Looking for any Apple receipt data
 * 3. Providing instructions for manual verification
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'circles-app-83b67'
});

async function checkUserSubscription() {
    const userId = '116841974455852261378'; // Brittany's user ID
    const userEmail = 'chamberlinbritt@gmail.com'; // For verification
    
    console.log('🔍 Manual Subscription Check for Brittany');
    console.log('==========================================\n');
    
    try {
        const db = admin.firestore();
        const userRef = db.collection('users').doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            console.log('❌ User not found in database');
            return;
        }
        
        const userData = userDoc.data();
        
        console.log('👤 User Information:');
        console.log(`   Email: ${userData.email || 'Not set'}`);
        console.log(`   Display Name: ${userData.displayName || 'Not set'}`);
        console.log(`   User ID: ${userId}`);
        console.log('');
        
        console.log('💳 Current Subscription Status:');
        console.log(`   Status: ${userData.subscriptionStatus || 'none'}`);
        console.log(`   Expiry Date: ${userData.subscriptionExpiryDate || 'None'}`);
        console.log(`   Apple Transaction ID: ${userData.appleOriginalTransactionId || 'None'}`);
        console.log(`   Last Receipt: ${userData.lastReceipt ? 'Present' : 'None'}`);
        console.log(`   Last Verification: ${userData.lastReceiptVerification || 'Never'}`);
        console.log('');
        
        console.log('📊 Circle Information:');
        const circlesSnapshot = await db.collection('circles').where('owner', '==', userId).get();
        console.log(`   Total Circles: ${circlesSnapshot.size}`);
        console.log(`   Free Tier Limit: 6 circles`);
        console.log(`   Status: ${circlesSnapshot.size > 6 ? '⚠️ Over limit' : '✅ Within limit'}`);
        console.log('');
        
        console.log('🔧 Recommended Actions:');
        
        if (userData.subscriptionStatus !== 'active') {
            console.log('1. ⚠️ Backend shows no active subscription');
            console.log('   → The iOS app needs to call /api/subscriptions/verify');
            console.log('   → This sends Apple receipt data to verify the subscription');
            console.log('');
            
            console.log('2. 📱 User should try these steps in the iOS app:');
            console.log('   → Log out and log back in');
            console.log('   → Go to Settings → Subscription Status');
            console.log('   → If it shows "Premium", the iOS app will auto-verify');
            console.log('   → If not, check Apple Subscription settings');
            console.log('');
            
            console.log('3. 🍎 Check Apple App Store:');
            console.log('   → Settings → [User Name] → Subscriptions');
            console.log('   → Look for "Circles" app subscription');
            console.log('   → Verify it shows as "Active"');
            console.log('');
            
            console.log('4. 🛠️ If subscription exists in Apple but not working:');
            console.log('   → This is an iOS app integration issue');
            console.log('   → The app is not calling the verification endpoint');
            console.log('   → May need to update the iOS app subscription handling');
            console.log('');
            
            // Temporary manual override option
            console.log('5. 🚨 TEMPORARY MANUAL OVERRIDE (Development Only):');
            console.log('   → If confirmed premium subscriber, can manually set status');
            console.log('   → This is NOT a permanent solution');
            console.log('   → Real fix needed in iOS app');
        } else {
            console.log('✅ Subscription appears active in backend');
            console.log('   → If user still getting errors, check iOS app caching');
            console.log('   → Try force-closing and reopening the app');
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
    
    console.log('\n==========================================');
    console.log('🎯 SUMMARY: The issue is iOS app → Backend communication');
    console.log('   The backend subscription logic is working correctly');
    console.log('   Brittany\'s iOS app has not sent her Apple subscription data');
    console.log('   This requires fixing the iOS subscription verification flow');
    
    process.exit(0);
}

checkUserSubscription();