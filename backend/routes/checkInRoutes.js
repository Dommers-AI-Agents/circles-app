// backend/routes/checkInRoutes.js
const express = require('express');
const requireSuperUser = require('../middleware/requireSuperUser');
const router = express.Router();
const checkInController = require('../controllers/checkInController');
const { protect } = require('../middleware/firebaseAuth');

// All routes require authentication
router.use(protect);

// Create a new check-in
router.post('/', checkInController.createCheckIn);

// Get active check-ins visible to user
router.get('/active', checkInController.getActiveCheckIns);

// Your check-in numbers + who's out now (the Check In screen's header)
router.get('/me/summary', checkInController.getMySummary);

// Get user's own active check-ins
router.get('/my-active', checkInController.getMyActiveCheckIns);

// Respond to a check-in (interested/going)
router.put('/:checkInId/respond', checkInController.respondToCheckIn);

// End check-in early
router.delete('/:checkInId', checkInController.endCheckIn);

// Get check-ins at a specific place
router.get('/at-place/:placeId', checkInController.getCheckInsAtPlace);

// Admin route to clean up expired check-ins
router.post('/cleanup', requireSuperUser, checkInController.cleanupExpiredCheckIns);

module.exports = router;