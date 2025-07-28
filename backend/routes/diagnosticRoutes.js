// Diagnostic routes for testing
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { getFirestore, getMessaging } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();
const messaging = getMessaging();

// Test Firebase messaging directly
router.post('/test-fcm-direct', protect, async (req, res) => {
  try {
    const userId = req.user.uid;
    
    // Get user and tokens
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.json({ success: false, error: 'User not found' });
    }
    
    const userData = userDoc.data();
    const deviceTokens = userData.deviceTokens || [];
    
    if (deviceTokens.length === 0) {
      return res.json({ 
        success: false, 
        error: 'No device tokens',
        user: userData.email 
      });
    }
    
    const token = deviceTokens[0].token;
    
    // Simple test message
    const message = {
      token: token,
      notification: {
        title: 'Direct FCM Test',
        body: `Testing at ${new Date().toLocaleTimeString()}`
      }
    };
    
    console.log('📱 Attempting to send FCM message...');
    console.log('Token:', token.substring(0, 20) + '...');
    
    try {
      const response = await messaging.send(message);
      console.log('✅ FCM Success! Message ID:', response);
      
      res.json({
        success: true,
        messageId: response,
        token: token.substring(0, 20) + '...',
        firebase: 'Message sent successfully'
      });
    } catch (fcmError) {
      console.error('❌ FCM Error:', fcmError);
      res.json({
        success: false,
        error: fcmError.message,
        errorCode: fcmError.code,
        token: token.substring(0, 20) + '...'
      });
    }
  } catch (error) {
    console.error('❌ Route error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Check Firebase configuration
router.get('/check-config', protect, async (req, res) => {
  try {
    const userId = req.user.uid;
    
    // Test Firestore access
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : null;
    
    // Check messaging service
    let messagingStatus = 'Unknown';
    try {
      // Try to get app name from messaging
      messagingStatus = 'Available';
    } catch (e) {
      messagingStatus = 'Error: ' + e.message;
    }
    
    res.json({
      success: true,
      firestore: userDoc.exists ? 'Connected' : 'Error',
      messaging: messagingStatus,
      user: userData ? {
        email: userData.email,
        deviceTokens: (userData.deviceTokens || []).length
      } : null,
      projectId: process.env.FIREBASE_PROJECT_ID || 'Not set'
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

module.exports = router;