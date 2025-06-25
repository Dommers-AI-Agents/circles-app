// backend/routes/messagingRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');

const {
  getConversations,
  createNewConversation,
  getMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  markMessagesAsRead,
  getUnreadCount
} = require('../controllers/messagingController');

// Apply authentication middleware to all routes
router.use(protect);

// Conversation routes
router.route('/conversations')
  .get(getConversations)
  .post(createNewConversation);

// Message routes for a specific conversation
router.route('/conversations/:conversationId/messages')
  .get(getMessages)
  .post(sendMessage);

// Mark messages as read in a conversation
router.post('/conversations/:conversationId/read', markMessagesAsRead);

// Individual message operations
router.route('/:messageId')
  .put(editMessage)
  .delete(deleteMessage);

// Get unread count
router.get('/unread-count', getUnreadCount);

module.exports = router;