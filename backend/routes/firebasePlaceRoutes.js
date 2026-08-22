// backend/routes/firebasePlaceRoutes.js
const express = require('express');
const {
  getPlacesByCircleId,
  getPlace,
  createPlace,
  updatePlace,
  deletePlace,
  searchPlaces,
  refreshPlaceFromGoogle,
  updatePlaceAddress,
  getUnresolvedPlaces,
  resolveImportedPlace,
  flagPlaceInfo,
  likePlace,
  getPlaceLikes,
  getPlaceSavers,
  getPlaceComments,
  addPlaceComment,
  deletePlaceComment,
  likeComment,
  addPlaceCommentReply,
  getPlaceCommentReplies,
  addExistingPlaceToCircle,
  trackPlaceView,
  movePlace,
  getPlacesByMultipleCircles,
  getMyPlacesForCheckIn,
  getMySaveOfVenue,
  migrateGooglePhotosToFirebase
} = require('../controllers/firebasePlaceController');
const {
  followPlace,
  unfollowPlace,
  getPlaceFollowers
} = require('../controllers/placeFollowController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// Place routes
router.route('/')
  .post(createPlace);

// Batch endpoint for fetching places from multiple circles
router.route('/batch')
  .post(getPlacesByMultipleCircles);

// Get all user's places for check-in
router.route('/my-places')
  .get(getMyPlacesForCheckIn);

// The caller's own save of a venue (by canonical/global place id) — powers
// per-save actions while viewing another user's copy of the venue
router.route('/my-save/:globalPlaceId')
  .get(getMySaveOfVenue);

// Own places awaiting on-device location resolution (background import queue)
router.route('/unresolved')
  .get(getUnresolvedPlaces);

// Migration endpoint for Google API photos
router.route('/migrate-photos')
  .post(migrateGooglePhotosToFirebase);

router.route('/search')
  .get(searchPlaces);

// More specific routes before generic :id route
router.route('/:id/refresh-google')
  .post(refreshPlaceFromGoogle);

router.route('/:id/update-address')
  .put(updatePlaceAddress);

// Stamp on-device Apple resolution onto an unmapped import
router.route('/:id/resolve')
  .put(resolveImportedPlace);

router.route('/:id/flag')
  .post(flagPlaceInfo);

router.route('/:id/like')
  .post(likePlace);

router.route('/:id/likes')
  .get(getPlaceLikes);

router.route('/:id/savers')
  .get(getPlaceSavers);

router.route('/:id/follow')
  .post(followPlace)
  .delete(unfollowPlace);

router.route('/:id/followers')
  .get(getPlaceFollowers);

router.route('/:id/comments')
  .get(getPlaceComments)
  .post(addPlaceComment);

router.route('/:placeId/comments/:commentId')
  .delete(deletePlaceComment);

router.route('/:placeId/comments/:commentId/like')
  .post(likeComment);

// Comment reply routes
router.route('/:id/comments/:commentId/replies')
  .get(getPlaceCommentReplies)
  .post(addPlaceCommentReply);

router.route('/:id/add-to-circle/:circleId')
  .post(addExistingPlaceToCircle);

router.route('/:id/track-view')
  .post(trackPlaceView);

router.route('/:id/move')
  .post(movePlace);

// Mark place as viewed
router.route('/:id/mark-viewed')
  .post(async (req, res) => {
    try {
      const userId = req.user.firebaseDocId || req.user.uid;
      const { id: placeId } = req.params;
      const { circleId } = req.body;
      
      const activityService = require('../services/activityService');
      await activityService.markPlaceAsViewed(userId, placeId, circleId);
      
      res.status(200).json({
        success: true,
        message: 'Place marked as viewed'
      });
    } catch (error) {
      console.error('Error marking place as viewed:', error);
      res.status(500).json({
        success: false,
        message: 'Failed to mark place as viewed',
        error: error.message
      });
    }
  });

router.route('/:id')
  .get(getPlace)
  .put(updatePlace)
  .delete(deletePlace);

module.exports = router;