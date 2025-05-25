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

router.route('/:id/share')
  .post(shareCircle);

router.route('/:id/follow')
  .post(followCircle);

router.route('/:id/unfollow')
  .post(unfollowCircle);

module.exports = router;