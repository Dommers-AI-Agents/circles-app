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
  // 2026.08-b: lightweight engagement moved to fractional coins ("nickels") —
  // a like is 1/20th of a coin, so tapping hearts can't out-earn creating
  // content. Comments stay a full coin (real feedback), capped. New: activity
  // reactions, moment likes, and the first received-engagement hook (your
  // moment getting liked pays YOU too). Old ledger rows keep their old
  // pricing via ruleVersion.
  // 2026.08-c: brand redemption codes (order-box cards / booth handouts) —
  // a real-world purchase touchpoint, priced like posting a moment.
  // 2026.08-d: check-in drops to half a coin — showing up is lighter than
  // creating content, and the fractional amount buys the dancing-leprechaun
  // deposit animation (Wesley).
  // 2026.08-e: first-place welcome gift — 25 coins the first time a user ever
  // adds a place, promised by the App Clip's generic "Join FavCircles" signup
  // (Wesley). Universal (all users, not just clip signups) so the promise is
  // true wherever it appears; stacks on the normal ADD_PLACE credit.
  // 2026.08-f: generic App Clip signup grants 50 FavCoins (Wesley). Store
  // reward points stay exclusive to scanning a specific enrolled store; a
  // generic "Join FavCircles" signup (no store) is rewarded in FavCoins, the
  // app-wide currency, instead. Once per user via clip_signup:<userId>.
  // 2026.08-g: weekly engagement bonus — the first qualifying place action
  // of each ISO week (add a place, share a circle, post a suggestion) pays a
  // 10-coin bonus on top of the action's own earn. Deliberately weekly, not a
  // daily streak: the app's job is episodic, and a daily streak would only
  // train people to ignore it. Once per week via weekly_goal:<uid>:<isoWeek>.
  RULE_VERSION: '2026.08-g',
  CLEARING_WINDOW_HOURS: 24,
  COINS: {
    ADD_PLACE: 3,
    CREATE_CIRCLE: 5,
    SHARE_CIRCLE: 2,
    CONNECTION_ACCEPTED: 2,
    REFERRAL_SIGNUP: 20,
    PLACE_ADOPTED: 5,
    SUGGESTION_POSTED: 1,
    CHECK_IN: 0.5,             // half a coin — and under 1, so the leprechaun dances
    PLACE_PHOTO: 1,
    MOMENT_POSTED: 2,
    PROFILE_COMPLETED: 5,
    PLACE_LIKED: 0.05,          // a nickel
    PHOTO_LIKED: 0.05,          // a nickel — hearting a photo in the carousel
    COMMENT_LIKED: 0.05,        // a nickel — hearting someone's comment
    PLACE_COMMENT: 1,           // real feedback — full coin, capped below
    USER_FOLLOWED: 0.10,        // a dime
    ACTIVITY_REACTION: 0.05,
    MOMENT_LIKED: 0.05,
    MOMENT_LIKE_RECEIVED: 0.05, // paid to the moment's OWNER
    BRAND_CODE_REDEEMED: 2,     // scanning the card that shipped in an order
    FIRST_PLACE_ADDED: 25,      // welcome gift — first place ever, once per user
    CLIP_SIGNUP: 50,            // generic App Clip signup (no store), once per user
    WEEKLY_GOAL: 10             // first qualifying place action of the ISO week
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
    // Fractional actions: generous counts, tiny value — 40 likes/day is
    // still only 2 coins
    PLACE_LIKED: 40,
    PHOTO_LIKED: 40,
    COMMENT_LIKED: 40,
    PLACE_COMMENT: 10,
    USER_FOLLOWED: 20,
    ACTIVITY_REACTION: 40,
    MOMENT_LIKED: 40,
    MOMENT_LIKE_RECEIVED: 100,  // passive — capped loosely
    BRAND_CODE_REDEEMED: 5,
    FIRST_PLACE_ADDED: 1,       // structurally once-ever via first_place:{uid}
    CLIP_SIGNUP: 1,             // structurally once-ever via clip_signup:{uid}
    WEEKLY_GOAL: 1              // structurally once-a-week via weekly_goal:{uid}:{isoWeek}
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
