// Subscription tier limits configuration
// These limits should match the iOS app limits defined in PremiumFeatures

const SUBSCRIPTION_LIMITS = {
  // Free tier limits
  FREE: {
    MAX_CIRCLES: 6,                    // Maximum number of circles a free user can create
    MAX_PLACES_PER_CIRCLE: 15,         // Maximum places per circle for free users
    MAX_TOTAL_PLACES: 90,              // Total theoretical max (6 circles × 15 places)
    CAN_EXPORT: false,                 // Export functionality
    CAN_IMPORT: false,                 // Importing places from other platforms
    CAN_SHARE_WITHOUT_WATERMARK: false, // Sharing without watermark
    // Event videos (Wes, 2026-10-10): short clips free, longer with Premium,
    // and a hard per-event cap for everyone so one account can't run up
    // storage and bandwidth
    EVENT_VIDEO_MAX_SECONDS: 15,
    EVENT_VIDEOS_PER_EVENT: 5,
    // Build my map from my photos (Wes, 2026-10-16): the first 25 places
    // free, nearest first, so a new map is their own neighborhood; the rest
    // with Premium. Its own allowance: the photo circle isn't held to
    // MAX_PLACES_PER_CIRCLE.
    PHOTO_PLACES: 25
  },
  
  // Trial tier (same as premium during trial period)
  TRIAL: {
    MAX_CIRCLES: Infinity,              // Unlimited circles
    MAX_PLACES_PER_CIRCLE: Infinity,    // Unlimited places per circle
    MAX_TOTAL_PLACES: Infinity,         // Unlimited total places
    CAN_EXPORT: true,
    CAN_IMPORT: true,
    CAN_SHARE_WITHOUT_WATERMARK: true,
    EVENT_VIDEO_MAX_SECONDS: 60,
    EVENT_VIDEOS_PER_EVENT: 20,
    PHOTO_PLACES: Infinity
  },

  // Premium tier (paid subscription)
  PREMIUM: {
    MAX_CIRCLES: Infinity,              // Unlimited circles
    MAX_PLACES_PER_CIRCLE: Infinity,    // Unlimited places per circle
    MAX_TOTAL_PLACES: Infinity,         // Unlimited total places
    CAN_EXPORT: true,
    CAN_IMPORT: true,
    CAN_SHARE_WITHOUT_WATERMARK: true,
    EVENT_VIDEO_MAX_SECONDS: 60,
    EVENT_VIDEOS_PER_EVENT: 20,
    PHOTO_PLACES: Infinity
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
  // The numbers come from the limits above, so changing a limit changes the message
  CIRCLE_LIMIT: `Free users can create up to ${SUBSCRIPTION_LIMITS.FREE.MAX_CIRCLES} circles. Upgrade to Premium for unlimited circles!`,
  PLACE_LIMIT: `Free users can add up to ${SUBSCRIPTION_LIMITS.FREE.MAX_PLACES_PER_CIRCLE} places per circle. Upgrade to Premium for unlimited places!`,
  EXPORT_LIMIT: 'Export functionality is available to Premium members only.',
  IMPORT_LIMIT: 'Importing places from other apps is available to Premium members only.',
  WATERMARK_LIMIT: 'Share without watermarks with Premium membership.',
  PHOTO_PLACES_LIMIT: `Your first ${SUBSCRIPTION_LIMITS.FREE.PHOTO_PLACES} places from your photos are free. Add the rest with Premium.`
};

module.exports = {
  SUBSCRIPTION_LIMITS,
  getTierForStatus,
  LIMIT_ERROR_MESSAGES
};