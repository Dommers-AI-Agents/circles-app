// backend/routes/connectionRoutes.js
const express = require('express');
const {
  getConnections,
  getConnectionById,
  sendConnectionRequest,
  acceptConnection,
  declineConnection,
  blockConnection,
  getSharedCirclesWithConnection,
  removeConnection,
  getActiveConnections,
  clearConnectionActivity,
  trackConnectionView
} = require('../controllers/connectionController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply authentication middleware to all routes
router.use(protect);

// Connection management routes
router.route('/')
  .get(getConnections);

router.route('/active')
  .get(getActiveConnections);

router.route('/invite')
  .post(sendConnectionRequest);

router.route('/:id/accept')
  .post(acceptConnection);

router.route('/:id/decline')
  .delete(declineConnection);

router.route('/:id/block')
  .post(blockConnection);

router.route('/:id/shared-circles')
  .get(getSharedCirclesWithConnection);

router.route('/:id/clear-activity')
  .post(clearConnectionActivity);

router.route('/:id/track-view')
  .post(trackConnectionView);

router.route('/:id')
  .get(getConnectionById)
  .delete(removeConnection);

// Admin endpoint to clean up old activities
router.post('/admin/cleanup-activities', async (req, res) => {
  try {
    const { daysToKeep = 1 } = req.body; // Default to 1 day (24 hours)
    const activityService = require('../services/activityService');
    
    console.log(`🧹 Running activity cleanup - keeping activities from last ${daysToKeep} days`);
    await activityService.cleanupOldActivity(daysToKeep);
    
    res.status(200).json({
      success: true,
      message: `Cleaned up activities older than ${daysToKeep} days`
    });
  } catch (error) {
    console.error('Error running activity cleanup:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cleanup activities',
      error: error.message
    });
  }
});

module.exports = router;