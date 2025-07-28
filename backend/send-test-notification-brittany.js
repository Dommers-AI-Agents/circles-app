#!/usr/bin/env node

// Script to send test notification to Brittany directly using Firebase Admin
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

// Initialize Firebase Admin
initializeApp({
  credential: applicationDefault(),
  projectId: 'circles-app-83b67'
});

const db = getFirestore();
const messaging = getMessaging();

async function sendTestNotificationToBrittany() {
  try {
    console.log('🔔 Preparing to send test notification to Brittany...');
    
    const userId = '116841974455852261378'; // Brittany's user ID
    
    // Get Brittany's device tokens
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.error('❌ User not found:', userId);
      return;
    }
    
    const userData = userDoc.data();
    console.log('👤 User data:', {
      displayName: userData.displayName,
      email: userData.email,
      hasDeviceTokens: !!userData.deviceTokens,
      deviceTokensType: typeof userData.deviceTokens
    });
    
    // Device tokens are stored as array of objects with token property
    let tokens = [];
    if (userData.deviceTokens) {
      console.log('📱 Device tokens structure:', userData.deviceTokens);
      
      if (Array.isArray(userData.deviceTokens)) {
        // Extract just the token strings from the objects
        tokens = userData.deviceTokens.map(t => t.token || t);
      } else if (typeof userData.deviceTokens === 'object') {
        // If stored as object with token as key
        tokens = Object.keys(userData.deviceTokens);
      }
    }
    
    console.log(`📱 Found ${tokens.length} device token(s) for Brittany`);
    console.log('🔑 Tokens:', tokens);
    
    if (tokens.length === 0) {
      console.error('❌ No device tokens found for Brittany');
      return;
    }
    
    // Prepare notification
    const notification = {
      title: 'Test Notification from Wesley 🎉',
      body: 'Hi Brittany! This is a test notification to ensure push notifications are working correctly.'
    };
    
    const data = {
      type: 'test',
      timestamp: new Date().toISOString(),
      testNotification: 'true',
      sentBy: 'Wesley'
    };
    
    // Send to all device tokens
    const results = await Promise.allSettled(
      tokens.map(token => 
        messaging.send({
          notification,
          data,
          token: token,
          apns: {
            payload: {
              aps: {
                badge: 1,
                sound: 'default'
              }
            }
          }
        })
      )
    );
    
    // Log results
    let successCount = 0;
    let failureCount = 0;
    
    results.forEach((result, index) => {
      if (result.status === 'fulfilled') {
        console.log(`✅ Successfully sent to token ${index + 1}`);
        successCount++;
      } else {
        console.log(`❌ Failed to send to token ${index + 1}:`, result.reason?.message || result.reason);
        failureCount++;
      }
    });
    
    console.log(`\n📊 Summary:`);
    console.log(`   Successful: ${successCount}`);
    console.log(`   Failed: ${failureCount}`);
    console.log(`\n✅ Test notification process complete!`);
    
  } catch (error) {
    console.error('❌ Error sending test notification:', error);
  }
}

// Run the script
sendTestNotificationToBrittany();