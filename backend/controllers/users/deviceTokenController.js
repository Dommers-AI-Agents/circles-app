// backend/controllers/users/deviceTokenController.js
// push device tokens and notification preferences
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const db = getFirestore();

// @desc    Register device token for push notifications
// @route   POST /api/users/device-token
// @access  Private
exports.registerDeviceToken = async (req, res, next) => {
  try {
    const { deviceToken, platform, replaceExisting } = req.body;
    
    if (!deviceToken || !platform) {
      return res.status(400).json({
        success: false,
        message: 'Please provide device token and platform'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    let deviceTokens = userData.deviceTokens || [];
    
    // If replaceExisting is true, clear all existing tokens for this platform
    if (replaceExisting) {
      console.log(`🔔 Replacing all existing ${platform} tokens for user ${req.user.uid}`);
      deviceTokens = deviceTokens.filter(t => t.platform !== platform);
    }
    
    // Check if this token already exists
    const existingTokenIndex = deviceTokens.findIndex(t => t.token === deviceToken);
    
    if (existingTokenIndex !== -1) {
      // Update existing token
      deviceTokens[existingTokenIndex] = {
        token: deviceToken,
        platform: platform,
        updatedAt: new Date().toISOString()
      };
    } else {
      // Add new token
      deviceTokens.push({
        token: deviceToken,
        platform: platform,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
    }
    
    await userRef.update({
      deviceTokens: deviceTokens,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Device token registered for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Device token registered successfully'
    });
  } catch (error) {
    console.error('Error registering device token:', error);
    next(error);
  }
};

// @desc    Remove device token
// @route   DELETE /api/users/device-token
// @access  Private
exports.removeDeviceToken = async (req, res, next) => {
  try {
    const { deviceToken } = req.body;
    
    if (!deviceToken) {
      return res.status(400).json({
        success: false,
        message: 'Please provide device token'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    const deviceTokens = userData.deviceTokens || [];
    
    // Remove the token
    const updatedTokens = deviceTokens.filter(t => t.token !== deviceToken);
    
    await userRef.update({
      deviceTokens: updatedTokens,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Device token removed for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Device token removed successfully'
    });
  } catch (error) {
    console.error('Error removing device token:', error);
    next(error);
  }
};

// @desc    Update notification preferences
// @route   PUT /api/users/notification-preferences
// @access  Private
exports.updateNotificationPreferences = async (req, res, next) => {
  try {
    const { notificationPreferences } = req.body;
    
    if (!notificationPreferences) {
      return res.status(400).json({
        success: false,
        message: 'Please provide notification preferences'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    await userRef.update({
      notificationPreferences: notificationPreferences,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`🔔 Notification preferences updated for user ${req.user.uid}`);
    
    res.status(200).json({
      success: true,
      message: 'Notification preferences updated successfully'
    });
  } catch (error) {
    console.error('Error updating notification preferences:', error);
    next(error);
  }
};
