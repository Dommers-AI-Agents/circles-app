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
  removeFriend,
  reorderCircles,
  registerDeviceToken,
  removeDeviceToken,
  updateNotificationPreferences,
  getUserPublicCircles,
  findDuplicateAccounts,
  checkDuplicateConnections,
  followUser,
  unfollowUser,
  getUserFollowers,
  getUserFollowing,
  addPinnedPlace,
  removePinnedPlace,
  getPinnedPlaces,
  reorderPinnedPlaces,
  recalculateFollowerCounts
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

router.route('/me/circles/reorder')
  .put(reorderCircles);

router.route('/me/duplicate-connections')
  .get(checkDuplicateConnections);

router.route('/find-duplicates')
  .post(findDuplicateAccounts);

router.route('/device-token')
  .post(registerDeviceToken)
  .delete(removeDeviceToken);

router.route('/notification-preferences')
  .put(updateNotificationPreferences);

router.route('/friend-request')
  .post(sendFriendRequest);

router.route('/friend-request/:id/accept')
  .post(respondToFriendRequest);

router.route('/friend-request/:id/reject')
  .post(respondToFriendRequest);

router.route('/friend/:id')
  .delete(removeFriend);

router.route('/:id/circles')
  .get(getUserPublicCircles);

router.route('/:id')
  .get(getUser);

// Follow/unfollow routes
router.route('/:id/follow')
  .post(followUser);

router.route('/:id/unfollow')
  .post(unfollowUser);

// Get followers/following (owner only)
router.route('/:id/followers')
  .get(getUserFollowers);

router.route('/:id/following')
  .get(getUserFollowing);

// Pinned places routes
router.route('/me/pinned-places')
  .get(getPinnedPlaces)
  .post(addPinnedPlace);

router.route('/me/pinned-places/reorder')
  .put(reorderPinnedPlaces);

router.route('/me/pinned-places/:placeId')
  .delete(removePinnedPlace);

// Recalculate follower counts
router.route('/:id/recalculate-counts')
  .post(recalculateFollowerCounts);

// Import getUserCircles from circleSharingController
const { getUserCircles } = require('../controllers/circleSharingController');

router.route('/:userId/circles')
  .get(getUserCircles);

module.exports = router;