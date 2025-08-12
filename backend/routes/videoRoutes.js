// backend/routes/videoRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  checkVideoQuota,
  initiateVideoUpload,
  completeVideoUpload,
  getPlaceVideos,
  getUserVideos,
  getVideoFeed,
  getVideoDetails,
  deleteVideo,
  updateVideo
} = require('../controllers/videoController');

// Quota check
router.get('/quota', protect, checkVideoQuota);

// Upload flow
router.post('/upload/initiate', protect, initiateVideoUpload);
router.post('/:videoId/upload/complete', protect, completeVideoUpload);

// Embedded video endpoints
router.post('/embed', protect, require('../controllers/videoController').addEmbeddedVideo);
router.get('/metadata', protect, require('../controllers/videoController').getVideoMetadata);

// Get videos
router.get('/place/:placeId', getPlaceVideos);
router.get('/user/:userId', getUserVideos);
router.get('/feed', protect, getVideoFeed);

// Reels-specific endpoints
router.get('/reels/feed', protect, require('../controllers/videoController').getReelsFeed);
router.get('/reels/user/:userId', protect, require('../controllers/videoController').getUserReels);
router.get('/reels/place/:placeId', protect, require('../controllers/videoController').getPlaceReels);
router.post('/reels/:videoId/like', protect, require('../controllers/videoController').likeReel);
router.delete('/reels/:videoId/like', protect, require('../controllers/videoController').unlikeReel);
router.post('/reels/:videoId/view', protect, require('../controllers/videoController').trackReelView);

router.get('/:videoId', getVideoDetails);

// Video management
router.delete('/:videoId', protect, deleteVideo);
router.put('/:videoId', protect, updateVideo);

module.exports = router;