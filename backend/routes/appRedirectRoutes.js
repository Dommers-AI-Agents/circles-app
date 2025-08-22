const express = require('express');
const router = express.Router();
const path = require('path');

// Serve the app redirect page for various deep link paths
// This handles email links that need to open the app

// Daily summary redirect
router.get('/daily-summary', (req, res) => {
  console.log('📱 App redirect: Daily summary link accessed');
  res.sendFile(path.join(__dirname, '../public/app-redirect.html'));
});

// Generic app redirect handler
// Can be used for other deep links in the future
router.get('/open', (req, res) => {
  const redirectPath = req.query.path || '';
  console.log(`📱 App redirect: Generic redirect to path: ${redirectPath}`);
  res.sendFile(path.join(__dirname, '../public/app-redirect.html'));
});

// Video deep link redirect
router.get('/video/:videoId', (req, res) => {
  console.log(`📱 App redirect: Video link for ID: ${req.params.videoId}`);
  res.sendFile(path.join(__dirname, '../public/app-redirect.html'));
});

// Circle deep link redirect
router.get('/circle/:circleId', (req, res) => {
  console.log(`📱 App redirect: Circle link for ID: ${req.params.circleId}`);
  res.sendFile(path.join(__dirname, '../public/app-redirect.html'));
});

// Connection invite redirect
router.get('/connect/:userId', (req, res) => {
  console.log(`📱 App redirect: Connection invite for user: ${req.params.userId}`);
  res.sendFile(path.join(__dirname, '../public/app-redirect.html'));
});

// Health check for app redirect routes
router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'App redirect routes are healthy',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;