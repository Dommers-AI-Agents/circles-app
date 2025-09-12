#!/usr/bin/env node

const admin = require('firebase-admin');
const path = require('path');
const readline = require('readline');

// Initialize Firebase Admin
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'circles-app-83b67'
});

const db = admin.firestore();

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

function question(query) {
    return new Promise(resolve => rl.question(query, resolve));
}

async function fixBrittanyPremium() {
    console.log('🔧 Manual Fix for Brittany\'s Premium Subscription\n');
    console.log('This script will manually set Brittany\'s subscription to active premium.');
    console.log('She will need to open the app to sync her actual Apple subscription.\n');
    
    const confirm = await question('Do you want to proceed? (yes/no): ');
    
    if (confirm.toLowerCase() !== 'yes') {
        console.log('Cancelled.');
        rl.close();
        process.exit(0);
    }
    
    try {
        // Find Brittany's user document
        const usersSnapshot = await db.collection('users')
            .where('email', '==', 'chamberlinbritt@gmail.com')
            .limit(1)
            .get();
        
        if (usersSnapshot.empty) {
            console.log('❌ User not found with email: chamberlinbritt@gmail.com');
            rl.close();
            process.exit(1);
        }
        
        const userDoc = usersSnapshot.docs[0];
        const userId = userDoc.id;
        
        console.log(`\n👤 Found user: ${userId}`);
        
        // Set expiry date to 30 days from now (temporary until she syncs)
        const expiryDate = new Date();
        expiryDate.setDate(expiryDate.getDate() + 30);
        
        // Update subscription status
        await userDoc.ref.update({
            subscriptionStatus: 'active',
            subscriptionExpiryDate: expiryDate.toISOString(),
            lastManualFix: new Date().toISOString(),
            manualFixNote: 'Manually activated premium - user needs to open app to sync with Apple'
        });
        
        console.log('✅ Successfully updated Brittany\'s subscription status to active!');
        console.log(`   - Status: active`);
        console.log(`   - Temporary Expiry: ${expiryDate.toISOString()}`);
        console.log('');
        console.log('📱 IMPORTANT: Brittany needs to:');
        console.log('   1. Open the Circles app');
        console.log('   2. Go to Settings → Subscription');
        console.log('   3. This will sync her Apple subscription automatically');
        console.log('');
        
        // Test if she can create circles now
        const subscriptionLimitService = require('./services/subscriptionLimitService');
        const canCreateResult = await subscriptionLimitService.canCreateCircle(userId);
        
        console.log('✅ Verification:');
        console.log(`   - Can create circles: ${canCreateResult.canCreate ? 'Yes ✅' : 'No ❌'}`);
        if (canCreateResult.canCreate) {
            console.log('   - She can now create unlimited circles!');
        }
        
    } catch (error) {
        console.error('❌ Error:', error);
        rl.close();
        process.exit(1);
    }
    
    rl.close();
    process.exit(0);
}

fixBrittanyPremium();