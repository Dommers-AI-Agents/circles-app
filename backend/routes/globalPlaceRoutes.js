// backend/routes/globalPlaceRoutes.js
// Routes for global place management

const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { perUserLimit } = require('../middleware/security');
const webVenueSearch = require('../services/webVenueSearch');
const { sendServiceError } = require('../utils/serviceError');

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

// Venue search for the web app's Add Place (no MapKit in a browser): Photon /
// OpenStreetMap, cached and polite (services/webVenueSearch). This router is
// mounted before firebasePlaceRoutes, so '/:id' there never sees it. The
// per-account limit is the fleet-wide one (perUserLimit), not an
// in-memory express-rate-limit that each instance counts on its own.
router.get('/web-search', perUserLimit({ bucket: 'web-venue-search', windowMs: 3600000, max: 300 }), async (req, res) => {
  try {
    const data = await webVenueSearch.searchVenues({ q: req.query.q, lat: req.query.lat, lng: req.query.lng });
    res.status(200).json({ success: true, data, attribution: webVenueSearch.ATTRIBUTION });
  } catch (error) {
    sendServiceError(res, error, { log: 'web venue search', fallbackMessage: 'Place search failed. Please try again.' });
  }
});

// Global place routes
router.route('/global/search')
  .get(perUserLimit({ bucket: 'global-search', windowMs: 3600000, max: 600 }), searchGlobalPlaces);

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
// One photo library per place: owner/manager/super-user arrange it
router.route('/global/:placeId/photos/order')
  .put(require('../controllers/globalPlaceController').reorderPlacePhotos);
router.route('/global/:placeId/photos/cover')
  .put(require('../controllers/globalPlaceController').setPlaceCoverPhoto);

// Shared details: store team / super-user, one path (venueDetailsService)
router.route('/global/:placeId/details')
  .patch(require('../controllers/globalPlaceController').updatePlaceDetails);

router.route('/global/:placeId/media/:photoId/like')
  .post(require('../controllers/globalPlaceController').likeGlobalPlaceUpload)
  .delete(require('../controllers/globalPlaceController').unlikeGlobalPlaceUpload);

module.exports = router;