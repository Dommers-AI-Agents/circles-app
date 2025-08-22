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

router.route('/:id/mark-viewed')
  .post(require('../controllers/circleController').markCircleAsViewed);

router.route('/:id/follow')
  .post(followCircle);

router.route('/:id/unfollow')
  .post(unfollowCircle);

router.route('/:id/places')
  .get(require('../controllers/placeController').getPlacesByCircleId);

router.route('/:id/places/reorder')
  .put(require('../controllers/placeController').reorderPlacesInCircle);

// Circle Groups endpoints
router.route('/groups')
  .get(require('../controllers/circleGroupController').getGroups)
  .post(require('../controllers/circleGroupController').createGroup);

router.route('/groups/:groupId')
  .get(require('../controllers/circleGroupController').getGroup)
  .put(require('../controllers/circleGroupController').updateGroup)
  .delete(require('../controllers/circleGroupController').deleteGroup);

router.route('/:id/group')
  .put(require('../controllers/circleGroupController').addCircleToGroup)
  .delete(require('../controllers/circleGroupController').removeCircleFromGroup);

module.exports = router;