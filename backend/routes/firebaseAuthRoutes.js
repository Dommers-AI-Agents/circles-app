// backend/routes/firebaseAuthRoutes.js
const express = require('express');
const {
  firebaseAuth,
  getMe,
  updateProfile,
  refreshToken
} = require('../controllers/firebaseAuthController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Public routes
router.post('/firebase', firebaseAuth);
router.post('/refresh-token', refreshToken);

// Protected routes
router.get('/me', protect, getMe);
router.put('/me', protect, updateProfile);

module.exports = router;