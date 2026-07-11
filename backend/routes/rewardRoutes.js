// backend/routes/rewardRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const rewardController = require('../controllers/rewardController');

// Admin guard — same Bearer ADMIN_SECRET convention as routes/adminRoutes.js
const adminAuth = (req, res, next) => {
  const adminSecret = process.env.ADMIN_SECRET;
  const authHeader = req.get('Authorization');

  if (adminSecret && authHeader === `Bearer ${adminSecret}`) {
    next();
  } else {
    res.status(403).json({ success: false, error: 'Unauthorized' });
  }
};

// Admin venue management (mounted before protect so it uses its own guard)
router.post('/admin/venues', adminAuth, rewardController.createVenue);
router.get('/admin/venues', adminAuth, rewardController.listVenues);

// Authenticated user endpoints
router.use(protect);
router.get('/me', rewardController.getMe);
router.post('/scan', rewardController.scan);
router.post('/sticker-save', rewardController.confirmStickerSave);
router.get('/balance', rewardController.getBalance);
router.get('/offers', rewardController.getOffers);
router.post('/redeem-offer', rewardController.redeemOffer);

// Super-user endpoints (in-app venue management + granting access)
const requireSuperUser = (req, res, next) => {
  if (req.user && req.user.isSuperUser === true) {
    next();
  } else {
    res.status(403).json({ success: false, error: 'Super-user access required' });
  }
};

router.post('/venues', requireSuperUser, rewardController.createVenueFromApp);
router.get('/venues', requireSuperUser, rewardController.listVenues);
router.post('/superusers', requireSuperUser, rewardController.setSuperUser);
router.post('/venues/:venueId/owner', requireSuperUser, rewardController.setVenueOwner);

// Venue-owner endpoints (self-service offers + earn rate; super-users pass
// the owner check automatically)
router.get('/my-venues', rewardController.getMyVenues);
router.post('/venues/:venueId/email-qr', rewardController.requireVenueOwner, rewardController.emailVenueQR);
router.post('/venues/:venueId/offers', rewardController.requireVenueOwner, rewardController.addOffer);
router.put('/venues/:venueId/offers/:offerId', rewardController.requireVenueOwner, rewardController.updateOffer);
router.patch('/venues/:venueId', rewardController.requireVenueOwner, rewardController.updateVenueSettings);
router.post('/venues/:venueId/register-code', rewardController.requireVenueOwner, rewardController.rotateRegisterCode);

module.exports = router;
