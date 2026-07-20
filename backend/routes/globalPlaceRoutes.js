// backend/routes/globalPlaceRoutes.js
// Routes for global place management

const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');

const {
  getGlobalPlace,
  matchGlobalPlace,
  searchGlobalPlaces,
  createOrGetGlobalPlace,
  createUserPlaceRelation,
  addPublicReview,
  uploadPlaceMedia,
  getUserPlaceRelation,
  updateUserPlaceRelation,
  getPhotosDebug
} = require('../controllers/globalPlaceController');

// All routes require authentication
router.use(protect);

// Global place routes
router.route('/global/search')
  .get(searchGlobalPlaces);

// Literal segment — must be declared before '/global/:placeId'
router.route('/global/match')
  .get(matchGlobalPlace);

router.route('/global')
  .post(createOrGetGlobalPlace);

router.route('/global/:placeId')
  .get(getGlobalPlace);

// Debug route for photos
router.route('/global/:placeId/photos-debug')
  .get(getPhotosDebug);

// User-place relationship routes
router.route('/global/:placeId/relations')
  .post(createUserPlaceRelation);

router.route('/global/:placeId/relations/:relationId')
  .put(updateUserPlaceRelation);

router.route('/global/:placeId/user-relation')
  .get(getUserPlaceRelation);

// Public content routes
router.route('/global/:placeId/reviews')
  .post(addPublicReview);

router.route('/global/:placeId/media')
  .post(uploadPlaceMedia);

// Import deleteUserPhoto from globalPlaceController
const { deleteUserPhoto } = require('../controllers/globalPlaceController');

router.route('/global/:placeId/media/:photoId')
  .delete(deleteUserPhoto);

// Like endpoints for Global Place uploads
router.route('/global/:placeId/media/:photoId/like')
  .post(require('../controllers/globalPlaceController').likeGlobalPlaceUpload)
  .delete(require('../controllers/globalPlaceController').unlikeGlobalPlaceUpload);

module.exports = router;