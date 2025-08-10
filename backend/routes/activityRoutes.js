// backend/routes/activityRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const activityController = require('../controllers/activityController');
const activityInteractionController = require('../controllers/activityInteractionController');

// Get network activities
router.get('/network/activities', protect, activityController.getNetworkActivities);

// Mark activities as read
router.put('/network/activities/mark-read', protect, activityController.markActivitiesAsRead);

// Activity reactions
router.post('/activities/:activityId/reactions', protect, activityInteractionController.addReaction);
router.post('/activities/:activityId/reactions/remove', protect, activityInteractionController.removeReaction);
router.delete('/activities/:activityId/reactions', protect, activityInteractionController.removeReaction);
router.get('/activities/:activityId/reactions', protect, activityInteractionController.getReactions);
router.get('/activities/:activityId/reactions/details', protect, activityInteractionController.getReactionDetails);

// Activity comments
router.post('/activities/:activityId/comments', protect, activityInteractionController.addComment);
router.get('/activities/:activityId/comments', protect, activityInteractionController.getComments);
router.delete('/activities/:activityId/comments/:commentId', protect, activityInteractionController.deleteComment);
router.post('/activities/comments/:commentId/like', protect, activityInteractionController.toggleCommentLike);

// Test endpoint to manually create activity (for debugging)
router.post('/test/create-activity', protect, async (req, res) => {
  try {
    const { createActivity } = require('../controllers/activityController');
    const activityId = await createActivity(
      'test_activity',
      req.user.uid,
      'test',
      'test123',
      'Test Activity',
      { test: true }
    );
    res.json({ 
      success: true, 
      activityId,
      message: 'Test activity created' 
    });
  } catch (error) {
    console.error('❌ Test activity creation failed:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

module.exports = router;