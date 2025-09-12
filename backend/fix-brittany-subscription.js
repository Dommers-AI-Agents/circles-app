#!/usr/bin/env node

/**
 * Emergency script to manually verify Brittany's subscription
 * This is a temporary fix while the iOS app subscription flow is being fixed
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'circles-app-83b67'
});

async function fixBrittanySubscription() {
    const userId = '116841974455852261378'; // Brittany's user ID
    
    console.log('🔧 Emergency Subscription Fix for Brittany');
    console.log('==========================================\n');
    
    try {
        const db = admin.firestore();
        const userRef = db.collection('users').doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            console.log('❌ User not found');
            return;
        }
        
        const userData = userDoc.data();
        
        console.log('👤 User: Brittany C (brittanyvans@gmail.com)');
        console.log(`📊 Current status: ${userData.subscriptionStatus || 'none'}`);
        console.log(`📈 Circle count: ${(await db.collection('circles').where('owner', '==', userId).get()).size}`);
        console.log('');
        
        // Manual verification (temporary fix)
        console.log('⚡ Applying manual subscription verification...');
        
        const updateData = {
            subscriptionStatus: 'active',
            subscriptionExpiryDate: null, // Ongoing subscription
            manuallyVerified: true,
            manualVerificationReason: 'iOS app failed to send Apple subscription data - emergency fix',
            manualVerificationDate: new Date().toISOString(),
            lastReceiptVerification: new Date().toISOString()
        };
        
        await userRef.update(updateData);
        
        // Add audit log
        await db.collection('subscriptionAuditLog').add({
            userId,
            action: 'emergency_manual_verification',
            previousStatus: userData.subscriptionStatus || 'none',
            newStatus: 'active',
            reason: 'iOS app failed to send Apple subscription data - emergency fix for confirmed premium user',
            timestamp: new Date(),
            performedBy: 'admin_script',
            userEmail: userData.email
        });
        
        console.log('✅ Subscription status updated to ACTIVE');
        console.log('✅ Audit log created');
        console.log('');
        console.log('🎯 IMPORTANT NOTES:');
        console.log('   1. This is a TEMPORARY fix');
        console.log('   2. The iOS app still needs to be fixed to send Apple subscription data');
        console.log('   3. Brittany should now be able to create unlimited circles');
        console.log('   4. The root cause (iOS app → backend communication) still needs addressing');
        console.log('');
        
        // Verify the fix works
        console.log('🔍 Testing fix...');
        const subscriptionLimitService = require('./services/subscriptionLimitService');
        const canCreateResult = await subscriptionLimitService.canCreateCircle(userId);
        
        if (canCreateResult.canCreate) {
            console.log('✅ SUCCESS: User can now create circles');
        } else {
            console.log('❌ FAILED: User still cannot create circles');
            console.log('   Error:', canCreateResult.error);
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
    
    process.exit(0);
}

fixBrittanySubscription();