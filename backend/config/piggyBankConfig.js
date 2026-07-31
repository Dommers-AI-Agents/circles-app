// backend/config/piggyBankConfig.js
//
// The FavCoin economy, in one versioned place. Every ledger row records the
// RULE_VERSION that priced it, so values can change later without rewriting
// history. Coins are deliberately valueless in-app (legal posture) — nothing
// here or downstream may imply monetary value.

module.exports = {
  RULE_VERSION: '2026.07-a',
  CLEARING_WINDOW_HOURS: 48,
  COINS: {
    ADD_PLACE: 10,
    CREATE_CIRCLE: 25,
    SHARE_CIRCLE: 15,
    CONNECTION_ACCEPTED: 20,
    REFERRAL_SIGNUP: 200,
    PLACE_ADOPTED: 30,
    SUGGESTION_POSTED: 5
  },
  DAILY_CAPS: {              // earns past the cap: action still succeeds, pays 0
    ADD_PLACE: 20,
    CREATE_CIRCLE: 5,
    SHARE_CIRCLE: 15,
    CONNECTION_ACCEPTED: 20,
    REFERRAL_SIGNUP: 5,
    PLACE_ADOPTED: 30,
    SUGGESTION_POSTED: 10
  },
  CREATE_CIRCLE_MIN_PLACES: 3,   // enforced at CLEARING time, not earn time
  CLAIM: { MIN_CONFIRMED_TO_CLAIM: 500, COINS_PER_CAT: 1 },  // Phase 4 placeholders
  CLEARING_BATCH_SIZE: 200,
  HISTORY_PAGE_SIZE: 25
};
