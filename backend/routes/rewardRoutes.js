// backend/routes/rewardRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { requireOwnerPremium } = require('../middleware/ownerPremium');
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
// Single-use brand loyalty codes (order-box cards, booth handouts)
router.post('/redeem-code', rewardController.redeemCode);
// Brand storefronts (account-anchored businesses / virtual stores)
router.put('/storefront', rewardController.updateStorefront);
router.get('/storefront/:userId', rewardController.getStorefront);
router.post('/venues/virtual', rewardController.createVirtualVenue);
// `by-place` is a literal segment, so this can't shadow /venues/:venueId/* routes
router.get('/venues/by-place/:placeId', rewardController.getVenueByPlace);
router.post('/venues/:venueId/claim', rewardController.claimVenue);
// Claim straight from a place page — works whether or not a venue is enrolled
router.post('/places/:placeId/claim', rewardController.claimPlace);

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
router.get('/claims', requireSuperUser, rewardController.listClaims);
router.post('/claims/:claimId/approve', requireSuperUser, rewardController.approveClaim);
router.post('/claims/:claimId/deny', requireSuperUser, rewardController.denyClaim);

// Venue-owner endpoints. Free owner tier: venue list, dashboard headline,
// window QR (scan-to-save). Business tier (requireOwnerPremium; super-users
// and ownerManuallyVerified bypass): offers, announcements, earn rate, and
// the register QR — the loyalty program.
router.get('/my-venues', rewardController.getMyVenues);
router.post('/email-ai-setup', rewardController.emailAiSetup);
router.get('/venues/:venueId/dashboard', rewardController.requireVenueOwner, rewardController.getVenueDashboard);
// Stat drill-downs (who follows / who saved / the scan ledger) are Business-
// tier detail, like the dashboard's monthly history
router.get('/venues/:venueId/followers', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.getVenueFollowers);
router.get('/venues/:venueId/savers', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.getVenueSavers);
router.get('/venues/:venueId/activity', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.getVenueActivity);
// Cover photo is basic storefront presence — free owner tier
router.put('/venues/:venueId/cover-photo', rewardController.requireVenueOwner, rewardController.setVenueCoverPhoto);
// Canonical place-record edit (name/description/category/phone/website) —
// free owner tier, same as the in-app tap-to-edit surface
router.patch('/venues/:venueId/place', rewardController.requireVenueOwner, rewardController.updateVenuePlace);
router.post('/venues/:venueId/email-qr', rewardController.requireVenueOwner, rewardController.emailVenueQR);
router.patch('/venues/:venueId/info', rewardController.requireVenueOwner, rewardController.updateVenueInfo);
router.post('/venues/:venueId/offers', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.addOffer);
router.put('/venues/:venueId/offers/:offerId', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.updateOffer);
router.post('/venues/:venueId/announcements', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.addAnnouncement);
router.put('/venues/:venueId/announcements/:announcementId', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.updateAnnouncement);
router.delete('/venues/:venueId/announcements/:announcementId', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.deleteAnnouncement);
router.patch('/venues/:venueId', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.updateVenueSettings);
router.post('/venues/:venueId/register-code', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.rotateRegisterCode);
router.post('/venues/:venueId/codes', rewardController.requireVenueOwner, requireOwnerPremium, rewardController.createRedemptionCodes);
router.get('/venues/:venueId/codes', rewardController.requireVenueOwner, rewardController.listRedemptionCodes);

module.exports = router;
