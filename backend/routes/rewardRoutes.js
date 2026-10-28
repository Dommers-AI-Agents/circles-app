// backend/routes/rewardRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { requireOwnerPremium } = require('../middleware/ownerPremium');
const {
  scan,
  confirmStickerSave,
  getBalance,
  redeemOffer,
  getOffers,
  getNearbyEvents,
  getVenueByPlace,
  getMe
} = require('../controllers/venues/rewardScanController');
const {
  createVenueFromApp,
  emailVenueQR,
  setSuperUser,
  setVenueOwner,
  enrollPlaceVenue,
  createVenue,
  listVenues,
  getVenueAdminDetail,
  syncAppClipExperiences
} = require('../controllers/venues/venueAdminController');
const {
  requireVenueOwner,
  getMyVenues,
  getVenueDashboard,
  getVenueFollowers,
  getVenueSavers,
  getVenueActivity,
  setVenueCoverPhoto,
  emailAiSetup,
  updateVenuePlace,
  updateVenueInfo,
  updateVenueSettings,
  rotateRegisterCode,
  getPrintAsset
} = require('../controllers/venues/venueOwnerController');
const {
  addOffer,
  updateOffer,
  addAnnouncement,
  updateAnnouncement,
  deleteAnnouncement
} = require('../controllers/venues/venueOffersController');
const {
  claimVenue,
  claimPlace,
  claimBusinessByDetails,
  listClaims,
  approveClaim,
  denyClaim
} = require('../controllers/venues/venueClaimsController');
const {
  updateStorefront,
  getStorefront,
  createVirtualVenue
} = require('../controllers/venues/storefrontController');
const {
  createRedemptionCodes,
  listRedemptionCodes,
  redeemCode
} = require('../controllers/venues/redemptionCodeController');
const {
  listVenueManagers,
  addVenueManager,
  removeVenueManager
} = require('../controllers/venues/venueManagersController');

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
router.post('/admin/venues', adminAuth, createVenue);
router.get('/admin/venues', adminAuth, listVenues);

// Authenticated user endpoints
router.use(protect);
router.get('/me', getMe);
router.post('/scan', scan);
router.post('/sticker-save', confirmStickerSave);
router.get('/balance', getBalance);
router.get('/offers', getOffers);
router.get('/nearby-events', getNearbyEvents);
router.post('/redeem-offer', redeemOffer);
// Single-use brand loyalty codes (order-box cards, booth handouts)
router.post('/redeem-code', redeemCode);
// Brand storefronts (account-anchored businesses / virtual stores)
router.put('/storefront', updateStorefront);
router.get('/storefront/:userId', getStorefront);
router.post('/venues/virtual', createVirtualVenue);
// `by-place` is a literal segment, so this can't shadow /venues/:venueId/* routes
router.get('/venues/by-place/:placeId', getVenueByPlace);
router.post('/venues/:venueId/claim', claimVenue);
// Claim straight from a place page — works whether or not a venue is enrolled
router.post('/places/:placeId/claim', claimPlace);
// Add-and-claim: business never saved by anyone — submit by details
router.post('/businesses/claim', claimBusinessByDetails);

// Super-user endpoints (in-app venue management + granting access)
const requireSuperUser = require('../middleware/requireSuperUser');

router.post('/venues', requireSuperUser, createVenueFromApp);
router.get('/venues', requireSuperUser, listVenues);
router.post('/superusers', requireSuperUser, setSuperUser);
router.post('/venues/:venueId/owner', requireSuperUser, setVenueOwner);
// Literal segment, like by-place: a super-user gets (or mints) the codes for any place
router.post('/venues/from-place/:placeId', requireSuperUser, enrollPlaceVenue);
// One store's full admin picture (requireVenueOwner just loads req.venue here)
router.get('/venues/:venueId/admin', requireSuperUser, requireVenueOwner, getVenueAdminDetail);
router.get('/claims', requireSuperUser, listClaims);
router.post('/claims/:claimId/approve', requireSuperUser, approveClaim);
router.post('/claims/:claimId/deny', requireSuperUser, denyClaim);

// Venue-owner endpoints. Free owner tier: venue list, dashboard headline,
// window QR (scan-to-save). Business tier (requireOwnerPremium; super-users
// and ownerManuallyVerified bypass): offers, announcements, earn rate, and
// the register QR — the loyalty program.
router.get('/my-venues', getMyVenues);
router.post('/email-ai-setup', emailAiSetup);
router.get('/venues/:venueId/dashboard', requireVenueOwner, getVenueDashboard);
// Stat drill-downs (who follows / who saved / the scan ledger) are Business-
// tier detail, like the dashboard's monthly history
router.get('/venues/:venueId/followers', requireVenueOwner, requireOwnerPremium, getVenueFollowers);
router.get('/venues/:venueId/savers', requireVenueOwner, requireOwnerPremium, getVenueSavers);
router.get('/venues/:venueId/activity', requireVenueOwner, requireOwnerPremium, getVenueActivity);
// Cover photo is basic storefront presence — free owner tier
router.put('/venues/:venueId/cover-photo', requireVenueOwner, setVenueCoverPhoto);
// Canonical place-record edit (name/description/category/phone/website) —
// free owner tier, same as the in-app tap-to-edit surface
router.patch('/venues/:venueId/place', requireVenueOwner, updateVenuePlace);
router.post('/venues/:venueId/email-qr', requireVenueOwner, emailVenueQR);
// Print-ready PDFs (sign / table tent / counter card, QR at 2-4 in). The
// handler gates kind=register to Business.
router.get('/venues/:venueId/print', requireVenueOwner, getPrintAsset);
// Super-users publish a store's own App Clip cards (per code URL) to App Store Connect
router.post('/venues/:venueId/app-clip-sync', requireSuperUser, requireVenueOwner, syncAppClipExperiences);
// Managers: the owner invites other accounts to run the store with them —
// free owner tier (team admin isn't a Business-tier tool). Mutations are
// gated to the primary owner inside the handlers.
router.get('/venues/:venueId/managers', requireVenueOwner, listVenueManagers);
router.post('/venues/:venueId/managers', requireVenueOwner, addVenueManager);
router.delete('/venues/:venueId/managers/:managerId', requireVenueOwner, removeVenueManager);
router.patch('/venues/:venueId/info', requireVenueOwner, updateVenueInfo);
router.post('/venues/:venueId/offers', requireVenueOwner, requireOwnerPremium, addOffer);
router.put('/venues/:venueId/offers/:offerId', requireVenueOwner, requireOwnerPremium, updateOffer);
router.post('/venues/:venueId/announcements', requireVenueOwner, requireOwnerPremium, addAnnouncement);
router.put('/venues/:venueId/announcements/:announcementId', requireVenueOwner, requireOwnerPremium, updateAnnouncement);
router.delete('/venues/:venueId/announcements/:announcementId', requireVenueOwner, requireOwnerPremium, deleteAnnouncement);
router.patch('/venues/:venueId', requireVenueOwner, requireOwnerPremium, updateVenueSettings);
router.post('/venues/:venueId/register-code', requireVenueOwner, requireOwnerPremium, rotateRegisterCode);
router.post('/venues/:venueId/codes', requireVenueOwner, requireOwnerPremium, createRedemptionCodes);
router.get('/venues/:venueId/codes', requireVenueOwner, listRedemptionCodes);
// Storefront: the menu (or services/products/rooms), the money buttons, and a
// gallery. Buttons are free — a working Reserve helps the customer whoever is
// paying. Menu and gallery are Business-tier, like announcements.
const storefront = require('../controllers/venues/venueStorefrontController');
router.get('/venues/:venueId/storefront', requireVenueOwner, storefront.getStorefront);
router.put('/venues/:venueId/slug', requireVenueOwner, storefront.setSlug); // the store's web address (order.favcircles.com/<slug>)
router.put('/venues/:venueId/storefront/actions', requireVenueOwner, storefront.updateActions);
router.put('/venues/:venueId/storefront/offerings', requireVenueOwner, requireOwnerPremium, storefront.updateOfferings);
router.put('/venues/:venueId/storefront/gallery', requireVenueOwner, requireOwnerPremium, storefront.updateGallery);
// The full menu, and scans (menu photo / hours sign / flyer → a draft), Business
router.put('/venues/:venueId/storefront/menu', requireVenueOwner, requireOwnerPremium, storefront.updateMenu);
router.post('/venues/:venueId/scan', requireVenueOwner, requireOwnerPremium, storefront.scan);
// Order ahead (pay at pickup): the store's orders and its on/off setting, Business
const venueOrders = require('../controllers/venues/venueOrdersController');
router.get('/venues/:venueId/orders', requireVenueOwner, requireOwnerPremium, venueOrders.list);
router.post('/venues/:venueId/orders/:orderId/:action', requireVenueOwner, requireOwnerPremium, venueOrders.act);
router.put('/venues/:venueId/ordering', requireVenueOwner, requireOwnerPremium, venueOrders.saveSettings);

module.exports = router;
