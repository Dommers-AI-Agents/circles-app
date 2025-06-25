// backend/routes/firebaseCircleRoutes.js
const express = require('express');
const {
  getMyCircles,
  getSharedCircles,
  getCircle,
  createCircle,
  updateCircle,
  deleteCircle,
  shareCircle,
  followCircle,
  unfollowCircle
} = require('../controllers/firebaseCircleController');
const {
  shareCircle: newShareCircle,
  revokeShare,
  getCircleShares
} = require('../controllers/circleSharingController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// Circle routes
router.route('/')
  .get(getMyCircles)
  .post(createCircle);

router.route('/me')
  .get(getMyCircles);

router.route('/shared')
  .get(getSharedCircles);

router.route('/:id')
  .get(getCircle)
  .put(updateCircle)
  .delete(deleteCircle);

// New sharing routes (replacing the old shareCircle)
router.route('/:id/share')
  .post(newShareCircle);

router.route('/:id/share/:shareId')
  .delete(revokeShare);

router.route('/:id/shares')
  .get(getCircleShares);

router.route('/:id/follow')
  .post(followCircle);

router.route('/:id/unfollow')
  .post(unfollowCircle);

module.exports = router;