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
    const { limit = 50, offset = 0, archived = 'false' } = req.query;
    const isArchived = archived === 'true';
    
    console.log('🔍 NOTIFICATION CONTROLLER: Fetching notifications');
    console.log('🔍 NOTIFICATION CONTROLLER: Limit:', limit, 'Offset:', offset, 'Archived:', isArchived);
    
    // Build query - fetch all notifications for user first
    // We'll filter archived status manually because Firestore's 'in' operator
    // doesn't match undefined values
    let query = db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc');
    
    // Get all notifications first (we'll filter after)
    const allNotificationsSnapshot = await query.get();
    
    // Filter by archived status manually
    const filteredNotifications = [];
    allNotificationsSnapshot.forEach(doc => {
      const notification = doc.data();
      // For active notifications: include if archived is not explicitly true
      // This handles undefined, null, and false values
      if (isArchived) {
        if (notification.archived === true) {
          filteredNotifications.push({ id: doc.id, ...notification });
        }
      } else {
        if (notification.archived !== true) {
          filteredNotifications.push({ id: doc.id, ...notification });
        }
      }
    });
    
    // Apply pagination manually
    const startIndex = parseInt(offset);
    const endIndex = startIndex + parseInt(limit);
    const paginatedNotifications = filteredNotifications.slice(startIndex, endIndex);
    
    console.log('✅ NOTIFICATION CONTROLLER: Notifications query executed');
    console.log('✅ NOTIFICATION CONTROLLER: Total notifications:', allNotificationsSnapshot.size);
    console.log('✅ NOTIFICATION CONTROLLER: Filtered notifications:', filteredNotifications.length);
    console.log('✅ NOTIFICATION CONTROLLER: Paginated notifications:', paginatedNotifications.length);
    
    // Check if there are more notifications
    const hasMore = filteredNotifications.length > endIndex;
    
    console.log('✅ NOTIFICATION CONTROLLER: Sending response with', paginatedNotifications.length, 'notifications');
    
    res.status(200).json({
      success: true,
      notifications: paginatedNotifications,
      hasMore: hasMore
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

// @desc    Archive all active notifications
// @route   PUT /api/notifications/archive-all
// @access  Private
exports.archiveAllNotifications = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const now = new Date().toISOString();
    
    // Get all active (non-archived) notifications for the user
    const activeSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .where('archived', 'in', [false, null]) // Include null for existing notifications
      .get();
    
    if (activeSnapshot.empty) {
      return res.status(200).json({
        success: true,
        message: 'No active notifications to archive'
      });
    }
    
    // Batch update all active notifications to archived
    const batch = db.batch();
    activeSnapshot.docs.forEach(doc => {
      batch.update(doc.ref, {
        archived: true,
        archivedAt: now
      });
    });
    
    await batch.commit();
    
    res.status(200).json({
      success: true,
      message: `Archived ${activeSnapshot.size} notifications`
    });
  } catch (error) {
    console.error('Error archiving all notifications:', error);
    next(error);
  }
};

// @desc    Delete a notification permanently
// @route   DELETE /api/notifications/:id
// @access  Private
exports.deleteNotification = async (req, res, next) => {
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
        message: 'Not authorized to delete this notification'
      });
    }
    
    // Delete the notification permanently
    await notificationRef.delete();
    
    res.status(200).json({
      success: true,
      message: 'Notification deleted permanently'
    });
  } catch (error) {
    console.error('Error deleting notification:', error);
    next(error);
  }
};

// @desc    Clear all archived notifications permanently
// @route   DELETE /api/notifications/archived
// @access  Private
exports.clearArchivedNotifications = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    
    // Get all archived notifications for the user
    const archivedSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .where('archived', '==', true)
      .get();
    
    if (archivedSnapshot.empty) {
      return res.status(200).json({
        success: true,
        message: 'No archived notifications to clear'
      });
    }
    
    // Batch delete all archived notifications
    const batch = db.batch();
    archivedSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    
    res.status(200).json({
      success: true,
      message: `Deleted ${archivedSnapshot.size} archived notifications permanently`
    });
  } catch (error) {
    console.error('Error clearing archived notifications:', error);
    next(error);
  }
};