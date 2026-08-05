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
  CLAIM: {
    MIN_CONFIRMED_TO_CLAIM: 500,   // a claim moves ALL confirmed coins, min this
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
