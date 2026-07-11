// backend/routes/networkRoutes.js
const express = require('express');
const {
  getSharedCircles,
  getCirclesSharedWithMe,
  getMyNetworkCircles,
  getUsersWithCircles,
  getUserCircles
} = require('../controllers/circleSharingController');
const { getNetworkPlacesInViewport } = require('../controllers/networkPlacesController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply authentication middleware to all routes
router.use(protect);

// Get network places within a map viewport (center + radius)
router.route('/places/viewport')
  .get(getNetworkPlacesInViewport);

// Network overview routes
router.route('/shared-circles')
  .get(getSharedCircles);

// Get circles that others have shared with me (editable)
router.route('/circles-shared-with-me')
  .get(getCirclesSharedWithMe);

// Get all circles from my network connections with myNetwork privacy
router.route('/my-network-circles')
  .get(getMyNetworkCircles);

// Get connected users with their circle counts
router.route('/users-with-circles')
  .get(getUsersWithCircles);

// Get circles for a specific connected user
router.route('/user-circles/:userId')
  .get(getUserCircles);

module.exports = router;