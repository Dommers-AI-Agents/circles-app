const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  prepareImport,
  executeImport,
  resolveGoogleListLink,
  getSwarmAuthUrl,
  swarmCallback,
  fetchSwarmData
} = require('../controllers/importController');

// Import saved places from other platforms (Mapstr, Google Takeout, Swarm)
router.post('/prepare', protect, prepareImport);
router.post('/execute', protect, executeImport);
// Shared Google Maps LIST link → its places (share-extension "save a whole list")
router.post('/resolve-google-list', protect, resolveGoogleListLink);

// Swarm (Foursquare) OAuth flow — callback is public, validated by state JWT
router.get('/swarm/auth-url', protect, getSwarmAuthUrl);
router.get('/swarm/callback', swarmCallback);
router.post('/swarm/fetch', protect, fetchSwarmData);

module.exports = router;
