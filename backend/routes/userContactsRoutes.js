// backend/routes/userContactsRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  syncContacts,
  getSuggestedUsers,
  inviteContacts
} = require('../controllers/userContactsController');

// Apply authentication middleware to all routes
router.use(protect);

// Sync contacts with existing users
router.post('/sync-contacts', syncContacts);

// Get suggested users (most active users)
router.get('/suggested', getSuggestedUsers);

// Send invitations to non-users
router.post('/invite-contacts', inviteContacts);

module.exports = router;