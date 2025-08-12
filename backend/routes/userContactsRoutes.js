// backend/routes/userContactsRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  syncContacts,
  getSuggestedUsers,
  inviteContacts
} = require('../controllers/userContactsController');
const {
  getDiscoverUsers,
  searchUsersAdvanced,
  updateUserLocation
} = require('../controllers/userDiscoveryController');

// Apply authentication middleware to all routes
router.use(protect);

// Sync contacts with existing users
router.post('/sync-contacts', syncContacts);

// Get suggested users (most active users)
router.get('/suggested', getSuggestedUsers);

// Send invitations to non-users
router.post('/invite-contacts', inviteContacts);

// User discovery endpoints
router.get('/discover', getDiscoverUsers);
router.get('/search', searchUsersAdvanced);
router.post('/update-location', updateUserLocation);

module.exports = router;