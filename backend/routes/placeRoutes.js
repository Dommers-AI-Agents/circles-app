// backend/routes/placeRoutes.js
const express = require('express');
const multer = require('multer');
const {
  getMyPlaces,
  getPlace,
  createPlace,
  updatePlace,
  uploadPlacePhotos,
  deletePlace,
  addPlaceToCircle,
  removePlaceFromCircle,
  searchPlaces
} = require('../controllers/placeController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// Configure multer for memory storage
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB limit per file
    files: 10 // Max 10 files
  }
});

// Apply auth middleware to all routes
router.use(protect);

router.route('/')
  .get(getMyPlaces)
  .post(createPlace);

router.route('/search')
  .get(searchPlaces);

router.route('/:id')
  .get(getPlace)
  .put(updatePlace)
  .delete(deletePlace);

router.route('/:id/upload-photos')
  .post(upload.array('photos', 10), uploadPlacePhotos);

router.route('/:id/add-to-circle/:circleId')
  .post(addPlaceToCircle);

router.route('/:id/remove-from-circle/:circleId')
  .delete(removePlaceFromCircle);

module.exports = router;
