// backend/controllers/notificationController.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get user's notifications
// @route   GET /api/notifications
// @access  Private
exports.getNotifications = async (req, res, next) => {
  console.log('🚀 NOTIFICATION CONTROLLER: getNotifications called');
  console.log('🚀 NOTIFICATION CONTROLLER: User ID:', req.user.uid);
  console.log('🚀 NOTIFICATION CONTROLLER: Query params:', req.query);
  
  try {
    const userId = req.user.uid;
    const { limit = 50, offset = 0 } = req.query;
    
    console.log('🔍 NOTIFICATION CONTROLLER: Fetching notifications');
    console.log('🔍 NOTIFICATION CONTROLLER: Limit:', limit, 'Offset:', offset);
    
    // Get notifications for the user, sorted by most recent
    const notificationsSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    console.log('✅ NOTIFICATION CONTROLLER: Notifications query executed');
    console.log('✅ NOTIFICATION CONTROLLER: Found', notificationsSnapshot.size, 'notifications');
    
    const notifications = serializeQuerySnapshot(notificationsSnapshot);
    
    console.log('✅ NOTIFICATION CONTROLLER: Sending response with', notifications.length, 'notifications');
    
    res.status(200).json({
      success: true,
      notifications: notifications,
      hasMore: notifications.length === parseInt(limit)
    });
  } catch (error) {
    console.error('❌ NOTIFICATION CONTROLLER: Error fetching notifications:', error);
    console.error('❌ NOTIFICATION CONTROLLER: Error stack:', error.stack);
    next(error);
  }
};

// @desc    Mark notification as read
// @route   PUT /api/notifications/:id/read
// @access  Private
exports.markNotificationAsRead = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const notificationId = req.params.id;
    
    // Get the notification to verify ownership
    const notificationRef = db.collection(COLLECTIONS.NOTIFICATIONS).doc(notificationId);
    const notificationDoc = await notificationRef.get();
    
    if (!notificationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found'
      });
    }
    
    const notification = notificationDoc.data();
    
    // Verify the notification belongs to the user
    if (notification.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this notification'
      });
    }
    
    // Update the notification
    await notificationRef.update({
      read: true,
      readAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Notification marked as read'
    });
  } catch (error) {
    console.error('Error marking notification as read:', error);
    next(error);
  }
};

// @desc    Get unread notification count
// @route   GET /api/notifications/unread-count
// @access  Private
exports.getUnreadCount = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    
    // Count unread notifications
    const unreadSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .where('read', '==', false)
      .get();
    
    const unreadCount = unreadSnapshot.size;
    
    res.status(200).json({
      success: true,
      unreadCount: unreadCount
    });
  } catch (error) {
    console.error('Error fetching unread count:', error);
    next(error);
  }
};

// @desc    Mark all notifications as read
// @route   PUT /api/notifications/read-all
// @access  Private
exports.markAllAsRead = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const now = new Date().toISOString();
    
    // Get all unread notifications for the user
    const unreadSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .where('read', '==', false)
      .get();
    
    // Batch update all unread notifications
    const batch = db.batch();
    unreadSnapshot.docs.forEach(doc => {
      batch.update(doc.ref, {
        read: true,
        readAt: now
      });
    });
    
    await batch.commit();
    
    res.status(200).json({
      success: true,
      message: `Marked ${unreadSnapshot.size} notifications as read`
    });
  } catch (error) {
    console.error('Error marking all notifications as read:', error);
    next(error);
  }
};