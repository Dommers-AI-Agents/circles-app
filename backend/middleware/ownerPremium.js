// backend/middleware/ownerPremium.js
// Gate for store-owner business-tier endpoints (announcements, offers, earn
// rate, register QR). Compose after protect + requireVenueOwner. Super users
// and ownerManuallyVerified accounts bypass; a paid subscription only covers
// the single venue it was purchased for (each store subscribes separately).
const { isOwnerPremiumForVenue, isOwnerPremiumById } = require('../services/ownerSubscriptionService');

const requireOwnerPremium = async (req, res, next) => {
  const venue = req.venue || null;
  const venueId = req.params.venueId || venue?.venueId;
  if (isOwnerPremiumForVenue(req.user, venueId, venue)) {
    return next();
  }
  // Managers ride the venue's billing owner's entitlement — the subscription
  // belongs to the store, not to whichever team member is doing the day's
  // admin. (requireVenueOwner has already established the caller is on the
  // venue's team; anyone here who isn't the billing owner is a manager.)
  if (venue && venue.ownerUserId && venue.ownerUserId !== req.user.uid) {
    try {
      if (await isOwnerPremiumById(venue.ownerUserId, venueId, venue)) {
        return next();
      }
    } catch (error) {
      console.error('⚠️ Manager premium check failed:', error.message);
    }
  }
  res.status(403).json({
    success: false,
    error: 'Business subscription required for this venue',
    upgradeRequired: true
  });
};

module.exports = { requireOwnerPremium };
