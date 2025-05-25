// backend/routes/userRoutes.js
const express = require('express');
const multer = require('multer');
const {
  getUsers,
  getUser,
  updateUser,
  uploadProfilePicture,
  getUserFriends,
  sendFriendRequest,
  acceptFriendRequest,
  rejectFriendRequest,
  removeFriend
} = require('../controllers/userController');
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
  .get(getUsers);

// IMPORTANT: /me route must come BEFORE /:id route
router.route('/me')
  .get((req, res, next) => {
    console.log('🔍 /me route hit - setting user ID from auth:', req.user.id);
    // Set the user ID from the authenticated user
    req.params.id = req.user.id;
    getUser(req, res, next);
  });

router.route('/:id')
  .get(getUser)
  .put(updateUser);

router.route('/:id/upload-profile-picture')
  .post(upload.single('profilePicture'), uploadProfilePicture);

router.route('/:id/friends')
  .get(getUserFriends);

router.route('/:id/friend-request')
  .post(sendFriendRequest);

router.route('/:id/accept-friend')
  .post(acceptFriendRequest);

router.route('/:id/reject-friend')
  .post(rejectFriendRequest);

router.route('/:id/remove-friend')
  .delete(removeFriend);

module.exports = router;