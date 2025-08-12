#!/usr/bin/env node

const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('../config/firebase-service-account.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: `https://${serviceAccount.project_id}.firebaseio.com`
});

const db = admin.firestore();

async function fixUserSubscriptionStatus(email) {
    try {
        console.log(`\n🔍 Checking subscription status for: ${email}`);
        
        // Find user by email
        const usersSnapshot = await db.collection('users')
            .where('email', '==', email)
            .limit(1)
            .get();
        
        if (usersSnapshot.empty) {
            console.log('❌ User not found');
            return;
        }
        
        const userDoc = usersSnapshot.docs[0];
        const userData = userDoc.data();
        const userId = userDoc.id;
        
        console.log(`\n📋 Current user data:`);
        console.log(`  - User ID: ${userId}`);
        console.log(`  - Display Name: ${userData.displayName}`);
        console.log(`  - Subscription Status: ${userData.subscriptionStatus || 'none'}`);
        console.log(`  - Trial Start Date: ${userData.trialStartDate || 'N/A'}`);
        console.log(`  - Trial End Date: ${userData.trialEndDate || 'N/A'}`);
        console.log(`  - Subscription Expiry: ${userData.subscriptionExpiryDate || 'N/A'}`);
        
        // Check if user has incorrect trial status
        if (userData.subscriptionStatus === 'trial' && !userData.trialStartDate) {
            console.log('\n⚠️  User has trial status but no trial start date - this is incorrect!');
            
            // Fix the subscription status
            console.log('🔧 Fixing subscription status to "none"...');
            await userDoc.ref.update({
                subscriptionStatus: 'none',
                subscriptionExpiryDate: null,
                trialStartDate: null,
                trialEndDate: null,
                updatedAt: new Date().toISOString()
            });
            
            console.log('✅ Subscription status fixed!');
            
            // Verify the fix
            const updatedDoc = await userDoc.ref.get();
            const updatedData = updatedDoc.data();
            console.log(`\n📋 Updated status: ${updatedData.subscriptionStatus}`);
        } else if (userData.subscriptionStatus === 'none') {
            console.log('\n✅ User already has correct "none" subscription status');
        } else {
            console.log(`\n📋 User has subscription status: ${userData.subscriptionStatus}`);
            
            // If trial, check if it's expired
            if (userData.subscriptionStatus === 'trial' && userData.trialEndDate) {
                const trialEnd = new Date(userData.trialEndDate);
                const now = new Date();
                if (trialEnd < now) {
                    console.log('⚠️  Trial has expired!');
                    console.log('🔧 Updating status to "expired"...');
                    await userDoc.ref.update({
                        subscriptionStatus: 'expired',
                        updatedAt: new Date().toISOString()
                    });
                    console.log('✅ Status updated to expired');
                } else {
                    const daysLeft = Math.ceil((trialEnd - now) / (1000 * 60 * 60 * 24));
                    console.log(`ℹ️  Trial is valid for ${daysLeft} more days`);
                }
            }
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    } finally {
        process.exit(0);
    }
}

// Check if email was provided as argument
const email = process.argv[2];
if (!email) {
    console.log('Usage: node fixSubscriptionStatus.js <email>');
    console.log('Example: node fixSubscriptionStatus.js greg@favcircles.com');
    process.exit(1);
}

// Run the fix
fixUserSubscriptionStatus(email);