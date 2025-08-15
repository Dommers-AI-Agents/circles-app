// backend/routes/notificationRoutes.js
const express = require('express');
const {
  getNotifications,
  markNotificationAsRead,
  getUnreadCount,
  markAllAsRead,
  archiveAllNotifications,
  deleteNotification,
  clearArchivedNotifications
} = require('../controllers/notificationController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// Notification routes
router.route('/')
  .get(getNotifications);

router.route('/unread-count')
  .get(getUnreadCount);

router.route('/read-all')
  .put(markAllAsRead);

router.route('/archive-all')
  .put(archiveAllNotifications);

router.route('/archived')
  .delete(clearArchivedNotifications);

router.route('/:id/read')
  .put(markNotificationAsRead);

router.route('/:id')
  .delete(deleteNotification);

module.exports = router;