// backend/routes/clipRoutes.js
// Routes backing the iOS App Clip (scan store QR → sign up → get points).

const express = require('express');
const rateLimit = require('express-rate-limit');
const { protect } = require('../middleware/firebaseAuth');
const clipController = require('../controllers/clipController');

const router = express.Router();

// The venue preview is public (the clip runs before the user has an account),
// so rate-limit it tighter than the general API limiter it also sits behind.
const clipPreviewLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  message: { success: false, error: 'Too many requests — please try again later.' }
});

router.get('/venue/:code', clipPreviewLimiter, clipController.getVenuePreview);
router.post('/install-converted', protect, clipController.installConverted);

module.exports = router;
