// backend/routes/firebaseAuthRoutes.js
const express = require('express');
const {
  firebaseAuth,
  register,
  login,
  getMe,
  updateProfile,
  refreshToken,
  facebookDataDeletion,
  forgotPassword
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

// Passkeys (WebAuthn) — same authLimiter as everything in this router
const passkey = require('../controllers/passkeyController');
const { validateEmailCheck, validatePasskeyRegisterVerify, validatePasskeyLoginVerify } = require('../middleware/validation');
router.post('/email-check', validateEmailCheck, passkey.emailCheck);
router.post('/passkey/register-options', validateEmailCheck, passkey.passkeyRegisterOptions);
router.post('/passkey/register-verify', validatePasskeyRegisterVerify, passkey.passkeyRegisterVerify);
router.post('/passkey/login-options', passkey.passkeyLoginOptions);
router.post('/passkey/login-verify', validatePasskeyLoginVerify, passkey.passkeyLoginVerify);
// Add a passkey to the CURRENT signed-in account (Settings enrollment flow)
router.post('/passkey/add-options', protect, passkey.passkeyAddOptions);
router.post('/passkey/add-verify', protect, passkey.passkeyAddVerify);
router.post('/refresh-token', refreshToken);
router.post('/forgot-password', forgotPassword);
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