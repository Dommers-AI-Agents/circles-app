// backend/routes/videoRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { uploadLimiter } = require('../middleware/security');
const {
  checkVideoQuota,
  initiateVideoUpload,
  completeVideoUpload,
  addEmbeddedVideo,
  getVideoMetadata,
  checkVideoStatus,
  removeMyMomentTag,
  deleteVideo,
  updateVideo
} = require('../controllers/video/videoUploadController');
const {
  getPlaceVideos,
  getUserVideos,
  getVideoFeed,
  getVideoDetails,
  getReelsFeed,
  getUserReels,
  getPlaceReels,
  getPublicVideoDetails
} = require('../controllers/video/videoFeedController');
const {
  likeReel,
  unlikeReel,
  trackReelView,
  getVideoComments,
  createVideoComment,
  getVideoActivity,
  getVideoLikes,
  deleteVideoComment,
  createVideoCommentReply,
  likeVideoComment,
  getVideoCommentReplies
} = require('../controllers/video/videoSocialController');
const {
  getVideoShareInfo,
  generateVideoShareLink
} = require('../controllers/video/videoShareController');

// Quota check
router.get('/quota', protect, checkVideoQuota);

// Upload flow - Apply uploadLimiter only to actual upload endpoints
router.post('/upload/initiate', protect, uploadLimiter, initiateVideoUpload);
router.post('/:videoId/upload/complete', protect, uploadLimiter, completeVideoUpload);

// Embedded video endpoints - Also limited as they create content
router.post('/embed', protect, uploadLimiter, addEmbeddedVideo);
router.get('/metadata', protect, getVideoMetadata);

// Get videos
router.get('/place/:placeId', getPlaceVideos);
router.get('/user/:userId', getUserVideos);
router.get('/feed', protect, getVideoFeed);

// Reels-specific endpoints
router.get('/reels/feed', protect, getReelsFeed);
router.get('/reels/user/:userId', protect, getUserReels);
router.get('/reels/place/:placeId', protect, getPlaceReels);
router.post('/reels/:videoId/like', protect, likeReel);
router.delete('/reels/:videoId/like', protect, unlikeReel);
router.post('/reels/:videoId/view', protect, trackReelView);

// Video likes endpoint
// "Remove me from this Moment" — tagged person only
router.delete('/:videoId/tags/me', protect, removeMyMomentTag);

router.get('/:videoId/likes', protect, getVideoLikes);

// Activity endpoint for videos
router.get('/:videoId/activity', protect, getVideoActivity);

// Share link generation
router.post('/:videoId/share', protect, generateVideoShareLink);
// Public: metadata for the /share/video/:videoId landing page
router.get('/:videoId/share-info', getVideoShareInfo);

// Public video access (no auth required)
router.get('/public/:videoId', getPublicVideoDetails);

// Comments endpoints for videos
router.get('/:videoId/comments', protect, getVideoComments);
router.post('/:videoId/comments', protect, createVideoComment);
router.delete('/:videoId/comments/:commentId', protect, deleteVideoComment);
router.post('/:videoId/comments/:commentId/like', protect, likeVideoComment);
router.post('/:videoId/comments/:commentId/replies', protect, createVideoCommentReply);
router.get('/:videoId/comments/:commentId/replies', protect, getVideoCommentReplies);

// `protect` is required: getVideoDetails resolves the viewer's relationship to
// the owner (followers/connections visibility), which needs req.user.uid.
// Unauthenticated/public access goes through GET /videos/public/:videoId.
router.get('/:videoId', protect, getVideoDetails);

// Video status check for polling
router.get('/:videoId/status', protect, checkVideoStatus);

// Video management
router.delete('/:videoId', protect, deleteVideo);
router.put('/:videoId', protect, updateVideo);

module.exports = router;