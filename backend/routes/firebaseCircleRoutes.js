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
  unfollowCircle,
  addEditor,
  removeEditor,
  getEditors,
  trackCircleView,
  likeCircle,
  getCircleLikes,
  getCircleComments,
  addCircleComment,
  deleteCircleComment
} = require('../controllers/firebaseCircleController');
const {
  shareCircle: newShareCircle,
  revokeShare,
  getCircleShares,
  validateShareToken
} = require('../controllers/circleSharingController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Public routes (no auth required)
router.route('/share/validate')
  .post(validateShareToken);

// Apply auth middleware to all remaining routes
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

// Editor management routes
router.route('/:id/editors')
  .get(getEditors)
  .post(addEditor);

router.route('/:id/editors/:userId')
  .delete(removeEditor);

// Activity tracking routes
router.route('/:id/track-view')
  .post(trackCircleView);

// Like and comment routes
router.route('/:id/like')
  .post(likeCircle);

router.route('/:id/likes')
  .get(getCircleLikes);

router.route('/:id/comments')
  .get(getCircleComments)
  .post(addCircleComment);

router.route('/:circleId/comments/:commentId')
  .delete(deleteCircleComment);

module.exports = router;