// backend/routes/activityRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const activityController = require('../controllers/activityController');

// Get network activities
router.get('/network/activities', protect, activityController.getNetworkActivities);

// Mark activities as read
router.put('/network/activities/mark-read', protect, activityController.markActivitiesAsRead);

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