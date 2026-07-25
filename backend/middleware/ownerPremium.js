// backend/middleware/ownerPremium.js
// Gate for store-owner business-tier endpoints (announcements, offers, earn
// rate, register QR). Compose after protect + requireVenueOwner. Super users
// and ownerManuallyVerified accounts bypass.
const { isOwnerPremiumUser } = require('../services/ownerSubscriptionService');

const requireOwnerPremium = (req, res, next) => {
  if (isOwnerPremiumUser(req.user)) {
    return next();
  }
  res.status(403).json({
    success: false,
    error: 'Business subscription required',
    upgradeRequired: true
  });
};

module.exports = { requireOwnerPremium };
