// backend/routes/linkedinAuthRoutes.js
const express = require('express');
const { linkedinAuth, getLinkedInAuthUrl } = require('../controllers/linkedinAuthController');

const router = express.Router();

// LinkedIn OAuth routes
router.post('/linkedin', linkedinAuth);
router.get('/linkedin/url', getLinkedInAuthUrl);

module.exports = router;