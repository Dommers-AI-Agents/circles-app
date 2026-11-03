// backend/routes/firebaseCircleRoutes.js
const express = require('express');
const { sendServiceError } = require('../utils/serviceError');
const {
  getMyCircles,
  getSharedCircles,
  getCircle,
  getCirclePublic,
  createCircle,
  updateCircle,
  deleteCircle,
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
  copyCircle,
  getCircleAdvice,
  mergeCircles
} = require('../controllers/firebaseCircleController');
const {
  shareCircle,
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
  .get(require('../middleware/firebaseAuth').optionalProtect, getCirclePublic);

// Apply auth middleware to all remaining routes
router.use(protect);

// Circle routes
router.route('/')
  .get(getMyCircles)
  .post(createCircle);

// Must precede /:id — otherwise "advisor" is parsed as a circle id.
router.route('/advisor')
  .get(getCircleAdvice);

router.route('/advisor/merge')
  .post(mergeCircles);

router.route('/me')
  .get(getMyCircles);

router.route('/shared')
  .get(getSharedCircles);

router.route('/:id')
  .get(getCircle)
  .put(updateCircle)
  .delete(deleteCircle);

// After a circle's privacy changes: how many of the owner's places in it set
// their own privacy (the app asks to bring them along when > 0), and "Yes,
// make them match" (Wes, 2026-11-03; services/circlePlacePrivacy.js)
router.get('/:id/place-privacy', async (req, res) => {
  try {
    const count = await require('../services/circlePlacePrivacy').countOwnPrivacy(req.params.id, req.user.uid);
    res.json({ success: true, data: { placesWithOwnPrivacy: count } });
  } catch (error) {
    sendServiceError(res, error, { log: 'place-privacy count failed', fallbackMessage: 'Something went wrong.' });
  }
});
router.post('/:id/place-privacy/match-circle', async (req, res) => {
  try {
    const updated = await require('../services/circlePlacePrivacy').matchCircle(req.params.id, req.user.uid);
    res.json({ success: true, data: { updated } });
  } catch (error) {
    sendServiceError(res, error, { log: 'place-privacy match failed', fallbackMessage: 'Something went wrong.' });
  }
});

// Sharing a circle with a named person. Writes a circleShares doc AND pushes
// them onto circles.sharedWith, which is the array the read gates consult.
router.route('/:id/share')
  .post(shareCircle);

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
      sendServiceError(res, error, { log: 'Error marking circle activities as viewed', fallbackMessage: 'Failed to mark circle activities as viewed' });
    }
  });

// Mark circle as viewed (alias for mark-activities-viewed)
router.route('/:id/mark-viewed')
  .post(async (req, res) => {
    try {
      const userId = req.user.firebaseDocId || req.user.uid;
      const { id: circleId } = req.params;
      
      const activityService = require('../services/activityService');
      await activityService.markCircleActivitiesAsViewed(userId, circleId);
      
      res.status(200).json({
        success: true,
        message: 'Circle marked as viewed'
      });
    } catch (error) {
      sendServiceError(res, error, { log: 'Error marking circle as viewed', fallbackMessage: 'Failed to mark circle as viewed' });
    }
  });

module.exports = router;