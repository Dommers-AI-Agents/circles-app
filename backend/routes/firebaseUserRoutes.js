// backend/routes/firebaseUserRoutes.js
const express = require('express');
const {
  getUser,
  updateUser,
  searchUsers,
  getFriends,
  sendFriendRequest,
  getFriendRequests,
  respondToFriendRequest,
  removeFriend
} = require('../controllers/firebaseUserController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// User routes
router.route('/search')
  .get(searchUsers);

router.route('/me')
  .get(getUser)
  .put(updateUser);

router.route('/me/friends')
  .get(getFriends);

router.route('/me/friend-requests')
  .get(getFriendRequests);

router.route('/friend-request')
  .post(sendFriendRequest);

router.route('/friend-request/:id/accept')
  .post(respondToFriendRequest);

router.route('/friend-request/:id/reject')
  .post(respondToFriendRequest);

router.route('/friend/:id')
  .delete(removeFriend);

router.route('/:id')
  .get(getUser);

module.exports = router;