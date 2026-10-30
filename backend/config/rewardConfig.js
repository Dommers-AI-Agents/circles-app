// backend/config/rewardConfig.js
// Point values and guards for the sticker rewards program.
// All values are server-side only — the iOS app renders whatever the API returns.

module.exports = {
  POINTS: {
    // The store owner sets every amount (Wes, 2026-10-30: "The store owner
    // needs to control points"); these are the defaults until they do.
    STICKER_SIGNUP: 25,    // joining FavCircles from the store's window QR (venue.joinPoints)
    STICKER_SAVE: 25,      // saving the store to a circle (venue.savePoints; was a fixed 50)
    VENUE_VISIT: 25        // default points per register-code (purchase) scan;
                           // venues override with their own earnRate
    // SHARE_CONVERSION retired 2026-08-10: not tied to a shop, so it has no
    // home under per-store loyalty. The sharer earns FavCoins instead
    // (piggyBankConfig COINS.PLACE_ADOPTED, same trigger).
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
