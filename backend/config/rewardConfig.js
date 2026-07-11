// backend/config/rewardConfig.js
// Point values and guards for the sticker rewards program.
// All values are server-side only — the iOS app renders whatever the API returns.

module.exports = {
  POINTS: {
    STICKER_SIGNUP: 100,   // new user signed up after scanning a window sticker
    STICKER_SAVE: 50,      // user saved the sticker venue's place to a circle
    VENUE_VISIT: 25,       // default points per register-code (purchase) scan;
                           // venues override with their own earnRate
    SHARE_CONVERSION: 50   // a place the user shared was added by someone else
  },

  // A sticker scan only counts as a "signup" if the account is this new
  SIGNUP_WINDOW_DAYS: 7,

  // Upper bound for owner-configured points-per-purchase (earnRate)
  EARN_RATE_MAX: 500,

  // Max venues returned by the browsable offers endpoint
  NEARBY_MAX_VENUES: 100,

  // How long a redemption voucher stays valid on screen
  VOUCHER_TTL_MINUTES: 5,

  // Venue sticker codes: 6 uppercase alphanumeric chars (same alphabet as referral codes)
  CODE_LENGTH: 6,

  APP_STORE_URL: 'https://apps.apple.com/us/app/favcircles/id6746807095'
};
