// backend/routes/dashboardRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { 
  getDashboard, 
  getCachedDashboard, 
  getHomeScreen, 
  getCacheStats, 
  refreshUserCache, 
  invalidateAllCache 
} = require('../controllers/dashboardController');

// Dashboard routes
router.get('/dashboard', protect, getDashboard);
router.get('/dashboard/cached', protect, getCachedDashboard);
router.get('/homescreen', protect, getHomeScreen); // Ultra-fast home screen data

// Cache management routes
router.get('/cache/stats', protect, getCacheStats);
router.post('/cache/refresh', protect, refreshUserCache);
router.post('/cache/invalidate-all', protect, invalidateAllCache);

module.exports = router;