// backend/routes/dashboardRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/authMiddleware');
const { getDashboard, getCachedDashboard } = require('../controllers/dashboardController');

// Dashboard routes
router.get('/dashboard', protect, getDashboard);
router.get('/dashboard/cached', protect, getCachedDashboard);

module.exports = router;