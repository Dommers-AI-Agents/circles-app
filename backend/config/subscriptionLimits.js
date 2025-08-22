// Subscription tier limits configuration
// These limits should match the iOS app limits defined in PremiumFeatures

const SUBSCRIPTION_LIMITS = {
  // Free tier limits
  FREE: {
    MAX_CIRCLES: 6,                    // Maximum number of circles a free user can create
    MAX_PLACES_PER_CIRCLE: 15,         // Maximum places per circle for free users
    MAX_TOTAL_PLACES: 90,              // Total theoretical max (6 circles × 15 places)
    CAN_EXPORT: false,                 // Export functionality
    CAN_SHARE_WITHOUT_WATERMARK: false // Sharing without watermark
  },
  
  // Trial tier (same as premium during trial period)
  TRIAL: {
    MAX_CIRCLES: Infinity,              // Unlimited circles
    MAX_PLACES_PER_CIRCLE: Infinity,    // Unlimited places per circle
    MAX_TOTAL_PLACES: Infinity,         // Unlimited total places
    CAN_EXPORT: true,
    CAN_SHARE_WITHOUT_WATERMARK: true
  },
  
  // Premium tier (paid subscription)
  PREMIUM: {
    MAX_CIRCLES: Infinity,              // Unlimited circles
    MAX_PLACES_PER_CIRCLE: Infinity,    // Unlimited places per circle
    MAX_TOTAL_PLACES: Infinity,         // Unlimited total places
    CAN_EXPORT: true,
    CAN_SHARE_WITHOUT_WATERMARK: true
  }
};

// Map subscription status to tier
const getTierForStatus = (subscriptionStatus) => {
  switch (subscriptionStatus) {
    case 'active':
    case 'grace_period':
      return SUBSCRIPTION_LIMITS.PREMIUM;
    case 'trial':
      return SUBSCRIPTION_LIMITS.TRIAL;
    case 'none':
    case 'expired':
    case 'cancelled':
    default:
      return SUBSCRIPTION_LIMITS.FREE;
  }
};

// Error messages for limit violations
const LIMIT_ERROR_MESSAGES = {
  CIRCLE_LIMIT: 'Free users can create up to 6 circles. Upgrade to Premium for unlimited circles!',
  PLACE_LIMIT: 'Free users can add up to 15 places per circle. Upgrade to Premium for unlimited places!',
  EXPORT_LIMIT: 'Export functionality is available to Premium members only.',
  WATERMARK_LIMIT: 'Share without watermarks with Premium membership.'
};

module.exports = {
  SUBSCRIPTION_LIMITS,
  getTierForStatus,
  LIMIT_ERROR_MESSAGES
};