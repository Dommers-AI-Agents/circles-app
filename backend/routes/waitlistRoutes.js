// backend/routes/waitlistRoutes.js — a customer's side of a store's waitlist
// (2026-11-09): join from the App Clip or place page, see your place, leave.
// The host's endpoints live under /api/rewards/venues/:venueId/waitlist.
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const waitlist = require('../controllers/venues/waitlistController');

const router = express.Router();
router.use(protect);
router.post('/:venueId/join', waitlist.join);
router.get('/:venueId/mine', waitlist.mine);
router.post('/entries/:entryId/leave', waitlist.leave);

module.exports = router;
