// backend/routes/globalPlaceRoutes.js
// Routes for global place management

const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/auth');

const {
  getGlobalPlace,
  searchGlobalPlaces,
  createOrGetGlobalPlace,
  createUserPlaceRelation,
  addPublicReview,
  uploadPlaceMedia,
  getUserPlaceRelation,
  updateUserPlaceRelation
} = require('../controllers/globalPlaceController');

// All routes require authentication
router.use(protect);

// Global place routes
router.route('/global/search')
  .get(searchGlobalPlaces);

router.route('/global')
  .post(createOrGetGlobalPlace);

router.route('/global/:placeId')
  .get(getGlobalPlace);

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

module.exports = router;