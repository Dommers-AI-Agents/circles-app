// backend/routes/authRoutes.js
const express = require('express');
const { register, login, firebaseAuth, getMe, logout } = require('../controllers/authController');
const { protect } = require('../middleware/auth');

const router = express.Router();

router.post('/register', register);
router.post('/login', login);
router.post('/firebase', firebaseAuth);
router.get('/me', protect, getMe);
router.get('/logout', protect, logout);

module.exports = router;