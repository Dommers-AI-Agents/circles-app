// backend/routes/networkRoutes.js
const express = require('express');
const {
  getSharedCircles
} = require('../controllers/circleSharingController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply authentication middleware to all routes
router.use(protect);

// Network overview routes
router.route('/shared-circles')
  .get(getSharedCircles);

module.exports = router;