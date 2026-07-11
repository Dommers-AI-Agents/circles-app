const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  prepareImport,
  executeImport,
  getSwarmAuthUrl,
  swarmCallback,
  fetchSwarmData
} = require('../controllers/importController');

// Import saved places from other platforms (Mapstr, Google Takeout, Swarm)
router.post('/prepare', protect, prepareImport);
router.post('/execute', protect, executeImport);

// Swarm (Foursquare) OAuth flow — callback is public, validated by state JWT
router.get('/swarm/auth-url', protect, getSwarmAuthUrl);
router.get('/swarm/callback', swarmCallback);
router.post('/swarm/fetch', protect, fetchSwarmData);

module.exports = router;
