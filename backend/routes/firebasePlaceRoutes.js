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
  likePlace,
  getPlaceComments,
  addPlaceComment,
  addExistingPlaceToCircle
} = require('../controllers/firebasePlaceController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// Place routes
router.route('/')
  .post(createPlace);

router.route('/search')
  .get(searchPlaces);

// More specific routes before generic :id route
router.route('/:id/refresh-google')
  .post(refreshPlaceFromGoogle);

router.route('/:id/like')
  .post(likePlace);

router.route('/:id/comments')
  .get(getPlaceComments)
  .post(addPlaceComment);

router.route('/:id/add-to-circle/:circleId')
  .post(addExistingPlaceToCircle);

router.route('/:id')
  .get(getPlace)
  .put(updatePlace)
  .delete(deletePlace);

module.exports = router;