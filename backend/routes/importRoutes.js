const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { perUserLimit } = require('../middleware/security');
const {
  prepareImport,
  executeImport,
  resolveGoogleListLink,
  getSwarmAuthUrl,
  swarmCallback,
  fetchSwarmData,
  importFromPhotos
} = require('../controllers/importController');

// Import saved places from other platforms (Mapstr, Google Takeout, Swarm)
router.post('/prepare', protect, perUserLimit({ bucket: 'import', windowMs: 3600000, max: 60 }), prepareImport);
router.post('/execute', protect, perUserLimit({ bucket: 'import', windowMs: 3600000, max: 60 }), executeImport);
// Build my map from my photos (batches of up to 25; free allowance, then Premium)
router.post('/photos', protect, perUserLimit({ bucket: 'import-photos', windowMs: 3600000, max: 120 }), importFromPhotos);
// Shared Google Maps LIST link → its places (share-extension "save a whole list")
router.post('/resolve-google-list', protect, resolveGoogleListLink);

// Swarm (Foursquare) OAuth flow — callback is public, validated by state JWT
router.get('/swarm/auth-url', protect, getSwarmAuthUrl);
router.get('/swarm/callback', swarmCallback);
router.post('/swarm/fetch', protect, fetchSwarmData);

module.exports = router;
