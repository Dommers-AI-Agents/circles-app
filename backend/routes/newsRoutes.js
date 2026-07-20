// backend/routes/newsRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { getSources, getFeed } = require('../controllers/newsController');

router.use(protect);
router.get('/sources', getSources);
router.get('/feed', getFeed);

module.exports = router;
