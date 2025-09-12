const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  blockUser,
  unblockUser,
  getBlockedUsers,
  checkIfBlocked
} = require('../controllers/blockController');

// All routes require authentication
router.use(protect);

// Block/unblock a user
router.route('/user/:userId')
  .post(blockUser)
  .delete(unblockUser);

// Get list of blocked users
router.get('/', getBlockedUsers);

// Check if a user is blocked
router.get('/check/:userId', checkIfBlocked);

module.exports = router;