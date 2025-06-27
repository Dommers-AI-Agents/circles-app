// backend/routes/connectionRoutes.js
const express = require('express');
const {
  getConnections,
  sendConnectionRequest,
  acceptConnection,
  declineConnection,
  blockConnection,
  getSharedCirclesWithConnection,
  removeConnection
} = require('../controllers/connectionController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply authentication middleware to all routes
router.use(protect);

// Connection management routes
router.route('/')
  .get(getConnections);

router.route('/invite')
  .post(sendConnectionRequest);

router.route('/:id/accept')
  .post(acceptConnection);

router.route('/:id/decline')
  .delete(declineConnection);

router.route('/:id/block')
  .post(blockConnection);

router.route('/:id/shared-circles')
  .get(getSharedCirclesWithConnection);

router.route('/:id')
  .delete(removeConnection);

module.exports = router;