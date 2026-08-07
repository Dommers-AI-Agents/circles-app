// backend/config/piggyBankConfig.js
//
// The FavCoin economy, in one versioned place. Every ledger row records the
// RULE_VERSION that priced it, so values can change later without rewriting
// history. Coins are deliberately valueless in-app (legal posture) — nothing
// here or downstream may imply monetary value.

module.exports = {
  // 2026.08-a: dollar-denomination rescale (Wesley) — values read like $1/$2/$5
  // so 100 FavCoins feels like $100. Old rows keep their 2026.07-a pricing;
  // existing balances deliberately untouched (founding-user head start).
  RULE_VERSION: '2026.08-a',
  CLEARING_WINDOW_HOURS: 24,
  COINS: {
    ADD_PLACE: 3,
    CREATE_CIRCLE: 5,
    SHARE_CIRCLE: 2,
    CONNECTION_ACCEPTED: 2,
    REFERRAL_SIGNUP: 20,
    PLACE_ADOPTED: 5,
    SUGGESTION_POSTED: 1,
    CHECK_IN: 1,
    PLACE_PHOTO: 1,
    MOMENT_POSTED: 2,
    PROFILE_COMPLETED: 5,
    PLACE_LIKED: 1,
    PLACE_COMMENT: 1,
    USER_FOLLOWED: 1
  },
  DAILY_CAPS: {              // earns past the cap: action still succeeds, pays 0
    ADD_PLACE: 20,
    CREATE_CIRCLE: 5,
    SHARE_CIRCLE: 15,
    CONNECTION_ACCEPTED: 20,
    REFERRAL_SIGNUP: 5,
    PLACE_ADOPTED: 30,
    SUGGESTION_POSTED: 10,
    CHECK_IN: 5,
    PLACE_PHOTO: 5,
    MOMENT_POSTED: 3,
    PROFILE_COMPLETED: 1,
    // Cheapest actions, tightest caps — these are the spam vectors
    PLACE_LIKED: 3,
    PLACE_COMMENT: 3,
    USER_FOLLOWED: 5
  },
  CREATE_CIRCLE_MIN_PLACES: 3,   // enforced at CLEARING time, not earn time
  CLAIM: {
    MIN_CONFIRMED_TO_CLAIM: 10,    // a claim moves ALL confirmed coins, min this
    FIRST_CLAIM_MIN: 1,            // a user's FIRST claim goes through at any
                                   // amount — the sooner someone sees real
                                   // coins land in their own wallet, the
                                   // sooner they believe the whole system
    COINS_PER_CAT: 1,              // supply-stretch lever (PIGGY_BANK_PLAN §8.4)
    CLAIM_FEE_COINS: 0,            // withheld from the claim; user bears fees (§8.4)
    MOJOS_PER_CAT: 1000,           // CAT2: 1 CAT = 1000 mojos on-chain
    SENT_TIMEOUT_HOURS: 24,        // unconfirmed past this → flag for review
    SENDING_GRACE_MINUTES: 10,     // claim_sending younger than this may be mid-RPC
    SETTLEMENT_BATCH_SIZE: 25
  },
  CLEARING_BATCH_SIZE: 200,
  HISTORY_PAGE_SIZE: 25
};
