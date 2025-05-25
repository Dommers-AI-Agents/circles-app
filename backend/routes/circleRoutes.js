// backend/routes/circleRoutes.js
const express = require('express');
const multer = require('multer');
const {
  getMyCircles,
  getSharedCircles,
  getCircle,
  createCircle,
  updateCircle,
  uploadCoverImage,
  deleteCircle,
  shareCircle,
  followCircle,
  unfollowCircle
} = require('../controllers/circleController');
const { protect } = require('../middleware/auth');

const router = express.Router();

// Configure multer for memory storage
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  }
});

// Apply auth middleware to all routes
router.use(protect);

router.route('/')
  .get(getMyCircles)
  .post(createCircle);

router.route('/me')
  .get(getMyCircles);

router.route('/shared')
  .get(getSharedCircles);

router.route('/:id')
  .get(getCircle)
  .put(updateCircle)
  .delete(deleteCircle);

router.route('/:id/upload-cover')
  .post(upload.single('coverImage'), uploadCoverImage);

router.route('/:id/share')
  .post(shareCircle);

router.route('/:id/follow')
  .post(followCircle);

router.route('/:id/unfollow')
  .post(unfollowCircle);

module.exports = router;