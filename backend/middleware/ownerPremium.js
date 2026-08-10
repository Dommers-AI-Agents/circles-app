// backend/middleware/ownerPremium.js
// Gate for store-owner business-tier endpoints (announcements, offers, earn
// rate, register QR). Compose after protect + requireVenueOwner. Super users
// and ownerManuallyVerified accounts bypass; a paid subscription only covers
// the single venue it was purchased for (each store subscribes separately).
const { isOwnerPremiumForVenue } = require('../services/ownerSubscriptionService');

const requireOwnerPremium = (req, res, next) => {
  const venueId = req.params.venueId || req.venue?.venueId;
  if (isOwnerPremiumForVenue(req.user, venueId, req.venue || null)) {
    return next();
  }
  res.status(403).json({
    success: false,
    error: 'Business subscription required for this venue',
    upgradeRequired: true
  });
};

module.exports = { requireOwnerPremium };
