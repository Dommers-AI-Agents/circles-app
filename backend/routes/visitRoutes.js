const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const visitController = require('../controllers/visitController');

// All routes require authentication
router.use(protect);

// Track a new visit
router.post('/track', visitController.trackVisit);

// Get user's visit history
router.get('/', visitController.getVisits);

// Get visit statistics
router.get('/stats', visitController.getVisitStats);

// Bulk add visits to circles
router.post('/bulk-add', visitController.bulkAddToCircles);

// Update visit tracking preferences
router.put('/settings/preferences', visitController.updateTrackingPreferences);

// Update exclusion settings
router.put('/settings/exclusions', visitController.updateExclusionSettings);

// Clear all visits for the user (MUST be before /:visitId)
router.delete('/clear-all', visitController.clearAllVisits);

// Update visit (mark as reviewed, dismissed, etc.)
router.put('/:visitId', visitController.updateVisit);

// Delete a visit (MUST be after /clear-all)
router.delete('/:visitId', visitController.deleteVisit);

module.exports = router;