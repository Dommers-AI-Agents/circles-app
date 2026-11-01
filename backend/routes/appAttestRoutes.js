// backend/routes/appAttestRoutes.js — App Attest (2026-11-01)
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const appAttest = require('../controllers/appAttestController');

const router = express.Router();
router.use(protect);
router.get('/challenge', appAttest.challenge);
router.post('/register', appAttest.register);

module.exports = router;
