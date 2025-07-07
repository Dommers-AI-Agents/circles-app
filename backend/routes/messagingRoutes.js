// backend/routes/messagingRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');

const {
  getConversations,
  getOrCreateDirectConversation,
  createNewConversation,
  getMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  markMessagesAsRead,
  getUnreadCount,
  deleteConversation,
  debugGetConversations
} = require('../controllers/messagingController');

// Apply authentication middleware to all routes
router.use(protect);

// Debug route (must come before parameterized routes)
router.get('/conversations/debug', debugGetConversations);

// Conversation routes
router.route('/conversations')
  .get(getConversations)
  .post(createNewConversation);

// Get or create direct conversation with specific user
router.post('/conversations/direct/:userId', getOrCreateDirectConversation);

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

// Delete a conversation
router.delete('/conversations/:conversationId', deleteConversation);

module.exports = router;