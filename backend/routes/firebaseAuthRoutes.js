// backend/routes/firebaseAuthRoutes.js
const express = require('express');
const {
  firebaseAuth,
  register,
  login,
  getMe,
  updateProfile,
  refreshToken,
  facebookDataDeletion
} = require('../controllers/firebaseAuthController');
const { protect } = require('../middleware/firebaseAuth');
const { 
  validateUserRegistration, 
  validateUserLogin 
} = require('../middleware/validation');

const router = express.Router();

// Public routes with validation
router.post('/register', validateUserRegistration, register);
router.post('/login', validateUserLogin, login);
router.post('/firebase', firebaseAuth);
router.post('/refresh-token', refreshToken);
router.post('/facebook-deauthorize', facebookDataDeletion);

// Protected routes
router.get('/me', protect, getMe);
router.put('/me', protect, updateProfile);

// Logout route (doesn't need protection as it just returns success)
router.post('/logout', (req, res) => {
  // In a JWT-based system, logout is handled client-side
  // The server just acknowledges the request
  res.status(200).json({
    success: true,
    message: 'Logged out successfully'
  });
});

module.exports = router;