#!/usr/bin/env node

require('dotenv').config();
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp({
  credential: cert(require('./config/firebase-service-account.json')),
  projectId: 'circles-app-83b67'
});

const db = getFirestore();
const messaging = getMessaging();

async function sendDailySummaryNotification() {
  console.log('📊 Sending Daily Summary Notification\n');
  
  const snapshot = await db.collection('users').where('email', '==', 'sgroiwes@gmail.com').get();
  if (snapshot.empty) {
    console.log('❌ User not found');
    return;
  }
  
  const user = snapshot.docs[0].data();
  const userId = snapshot.docs[0].id;
  
  console.log('👤 User:', user.displayName);
  console.log('📧 Email:', user.email);
  
  if (!user.deviceTokens || user.deviceTokens.length === 0) {
    console.log('❌ No device tokens found!');
    return;
  }
  
  // Extract actual token strings
  const tokens = user.deviceTokens
    .map(t => typeof t === 'object' ? t.token : t)
    .filter(t => t && typeof t === 'string');
  
  console.log(`📱 Found ${tokens.length} valid tokens\n`);
  
  // Create daily summary notification with realistic data
  const notification = {
    title: 'Your Daily Summary',
    body: '📍 5 new places • 👥 2 new connections • 💬 3 messages'
  };
  
  const data = {
    type: 'daily_summary',
    newPlaces: '5',
    newConnections: '2', 
    unreadMessages: '3',
    placeComments: '1',
    placeLikes: '4',
    placeCategories: JSON.stringify({ restaurants: 3, cafes: 2 }),
    topContributors: JSON.stringify([
      { name: 'Sarah', count: 2 },
      { name: 'Mike', count: 1 }
    ]),
    summaryDate: new Date().toISOString().split('T')[0]
  };
  
  const message = {
    notification,
    data,
    apns: {
      payload: {
        aps: {
          'mutable-content': 1,
          sound: 'default',
          badge: 0
        }
      }
    },
    tokens: tokens
  };
  
  console.log('📤 Sending daily summary notification...\n');
  
  try {
    const response = await messaging.sendEachForMulticast(message);
    
    console.log('📊 Results:');
    console.log(`✅ Successful: ${response.successCount}`);
    console.log(`❌ Failed: ${response.failureCount}`);
    
    if (response.failureCount > 0) {
      console.log('\n❌ Failed tokens:');
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          console.log(`   Token ${idx + 1}: ${resp.error?.message}`);
        }
      });
    }
    
    if (response.successCount > 0) {
      console.log('\n✅ Daily Summary notification sent successfully!');
      console.log('📱 Check your iOS device for the notification');
      console.log('💡 Tap it to see the new integrated daily summary view in the Home tab!');
    } else {
      console.log('\n⚠️  No notifications were sent successfully.');
      console.log('\n📱 To fix this:');
      console.log('1. Open the Circles app on your iOS device');
      console.log('2. Go to Profile → Settings → Push Notifications');
      console.log('3. Make sure notifications are enabled');
      console.log('4. Try logging out and back in to refresh your token');
    }
    
  } catch (error) {
    console.error('❌ Error sending notification:', error);
  }
}

sendDailySummaryNotification();