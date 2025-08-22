// backend/routes/videoRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { uploadLimiter } = require('../middleware/security');
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

// Upload flow - Apply uploadLimiter only to actual upload endpoints
router.post('/upload/initiate', protect, uploadLimiter, initiateVideoUpload);
router.post('/:videoId/upload/complete', protect, uploadLimiter, completeVideoUpload);

// Embedded video endpoints - Also limited as they create content
router.post('/embed', protect, uploadLimiter, require('../controllers/videoController').addEmbeddedVideo);
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

// Video likes endpoint
router.get('/:videoId/likes', protect, require('../controllers/videoController').getVideoLikes);

// Activity endpoint for videos
router.get('/:videoId/activity', protect, require('../controllers/videoController').getVideoActivity);

// Share link generation
router.post('/:videoId/share', protect, require('../controllers/videoController').generateVideoShareLink);

// Public video access (no auth required)
router.get('/public/:videoId', require('../controllers/videoController').getPublicVideoDetails);

// Comments endpoints for videos
router.get('/:videoId/comments', protect, require('../controllers/videoController').getVideoComments);
router.post('/:videoId/comments', protect, require('../controllers/videoController').createVideoComment);
router.delete('/:videoId/comments/:commentId', protect, require('../controllers/videoController').deleteVideoComment);
router.post('/:videoId/comments/:commentId/like', protect, require('../controllers/videoController').likeVideoComment);
router.post('/:videoId/comments/:commentId/replies', protect, require('../controllers/videoController').createVideoCommentReply);
router.get('/:videoId/comments/:commentId/replies', protect, require('../controllers/videoController').getVideoCommentReplies);

router.get('/:videoId', getVideoDetails);

// Video status check for polling
router.get('/:videoId/status', protect, require('../controllers/videoController').checkVideoStatus);

// Video management
router.delete('/:videoId', protect, deleteVideo);
router.put('/:videoId', protect, updateVideo);

module.exports = router;