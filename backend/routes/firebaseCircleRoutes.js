// backend/routes/firebaseCircleRoutes.js
const express = require('express');
const {
  getMyCircles,
  getSharedCircles,
  getCircle,
  getCirclePublic,
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
  deleteCircleComment,
  addCommentReply,
  getCommentReplies,
  copyCircle
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

router.route('/:id/public')
  .get(getCirclePublic);

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

// Comment reply routes
router.route('/:id/comments/:commentId/replies')
  .get(getCommentReplies)
  .post(addCommentReply);

// Copy circle route
router.route('/:id/copy')
  .post(copyCircle);

// Mark circle activities as viewed
router.route('/:id/mark-activities-viewed')
  .post(async (req, res) => {
    try {
      const userId = req.user.firebaseDocId || req.user.uid;
      const { id: circleId } = req.params;
      
      const activityService = require('../services/activityService');
      await activityService.markCircleActivitiesAsViewed(userId, circleId);
      
      res.status(200).json({
        success: true,
        message: 'Circle activities marked as viewed'
      });
    } catch (error) {
      console.error('Error marking circle activities as viewed:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to mark circle activities as viewed',
        error: error.message
      });
    }
  });

module.exports = router;