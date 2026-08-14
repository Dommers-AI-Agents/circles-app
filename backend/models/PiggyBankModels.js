// backend/models/PiggyBankModels.js
//
// Piggy bank (FavCoin) collections, factories, and the dedup-key builder.
// SEPARATE from the sticker rewards system (StickerModels/rewardEvents) —
// that's store loyalty; this is the contribution economy. Parallel systems.

const piggyBankConfig = require('../config/piggyBankConfig');

const PIGGY_COLLECTIONS = {
  LEDGER: 'piggyLedger',   // append-only, doc ID = dedup key
  BANKS: 'piggyBanks'      // materialized balance, doc ID = userId
};

const PIGGY_EVENT_TYPES = [
  'add_place',
  'create_circle',
  'share_circle',
  'connection_accepted',
  'referral_signup',
  'place_adopted',
  'suggestion_posted',
  // 2026.08-a additions
  'check_in',
  'place_photo',
  'moment_posted',
  'profile_completed',
  'place_liked',
  'place_comment',
  'user_followed',
  // 2026.08-b additions (fractional engagement)
  'activity_reaction',
  'moment_liked',
  'moment_like_received',
  // 2026.08-c: brand redemption codes
  'brand_code_redeemed',
  // 2026.08-d: carousel photo hearts
  'photo_liked'
];

// Earn statuses and claim statuses are disjoint vocabularies on the same
// ledger: clearing queries (status=='pending') can never see claim rows, and
// settlement queries (claim_*) can never see earns. Claim rows also carry no
// clearAt, keeping them out of the (status, clearAt) index entirely.
const PIGGY_STATUSES = [
  'pending', 'confirmed', 'reversed', 'held',                       // earns
  'claim_pending', 'claim_sending', 'claim_sent', 'settled', 'claim_failed' // claims
];

// Doc IDs cannot contain '/', and '.' segments are reserved (same rule as
// StickerModels.sanitizeKeyPart — duplicated here so the two systems never
// grow a load-order dependency on each other).
const sanitizeKeyPart = (part) => String(part).replace(/[/.]/g, '_');

/// The dedup key IS the idempotency guarantee: one ledger doc can ever exist
/// per key, enforced by ref.create(). Every rule about "can this be earned
/// twice" lives in how the key is built:
///
///   add_place:{uid}:{globalPlaceId||placeDocId}  re-adding a venue never pays twice
///   create_circle:{uid}:{circleId}
///   share_circle:{uid}:{circleId}:{targetUserId}
///   connection:{min uid}:{max uid}:{beneficiary}  order-independent per pair,
///                                                 one row per beneficiary
///   referral:{inviteeUserId}                      one payout per new human ever
///   adopted:{sharerUid}:{globalPlaceId||googlePlaceId}:{adderUid}
///   suggestion:{uid}:{suggestionId}
function derivePiggyDedupKey(eventType, parts = {}) {
  const s = sanitizeKeyPart;
  switch (eventType) {
    case 'add_place': {
      // Venue identity must be DETERMINISTIC across linking outcomes, or an
      // add that linked and a re-add that didn't would mint different keys
      // and pay twice. venueKey (google:<id> / manual:<name>:<address>) is
      // computable from the place itself on every add, so it leads; the
      // canonical global id and raw doc id are fallbacks for degenerate docs.
      const venue = parts.venueKey || parts.globalPlaceId || parts.placeId;
      if (!parts.userId || !venue) return null;
      return `add_place:${s(parts.userId)}:${s(venue)}`;
    }
    case 'create_circle':
      if (!parts.userId || !parts.circleId) return null;
      return `create_circle:${s(parts.userId)}:${s(parts.circleId)}`;
    case 'share_circle':
      if (!parts.userId || !parts.circleId || !parts.targetUserId) return null;
      return `share_circle:${s(parts.userId)}:${s(parts.circleId)}:${s(parts.targetUserId)}`;
    case 'connection_accepted': {
      // Pair key is order-independent so request/accept cycles can't farm it;
      // beneficiary suffix gives each side of the pair exactly one row.
      if (!parts.userId || !parts.otherUserId) return null;
      const [a, b] = [String(parts.userId), String(parts.otherUserId)].sort();
      return `connection:${s(a)}:${s(b)}:${s(parts.userId)}`;
    }
    case 'referral_signup':
      if (!parts.inviteeId) return null;
      return `referral:${s(parts.inviteeId)}`;
    case 'place_adopted': {
      const venue = parts.globalPlaceId || parts.googlePlaceId;
      if (!parts.userId || !venue || !parts.adderUserId) return null;
      return `adopted:${s(parts.userId)}:${s(venue)}:${s(parts.adderUserId)}`;
    }
    case 'suggestion_posted':
      if (!parts.userId || !parts.suggestionId) return null;
      return `suggestion:${s(parts.userId)}:${s(parts.suggestionId)}`;
    case 'brand_code_redeemed':
      // Keyed on the code alone: codes are single-use, so one payout ever
      // per code no matter who races the redemption.
      if (!parts.code) return null;
      return `brand_code:${s(parts.code)}`;
    case 'check_in': {
      // Once per venue per UTC day — the day segment IS the repeat rule.
      const venue = parts.globalPlaceId || parts.placeId;
      if (!parts.userId || !venue) return null;
      const day = new Date().toISOString().slice(0, 10);
      return `check_in:${s(parts.userId)}:${s(venue)}:${day}`;
    }
    case 'place_photo': {
      // First photo you contribute to a venue, ever — more photos of the
      // same place add little, so they pay nothing.
      const venue = parts.globalPlaceId || parts.placeId;
      if (!parts.userId || !venue) return null;
      return `place_photo:${s(parts.userId)}:${s(venue)}`;
    }
    case 'moment_posted':
      if (!parts.userId || !parts.videoId) return null;
      return `moment:${s(parts.userId)}:${s(parts.videoId)}`;
    case 'profile_completed':
      // Once per account, ever.
      if (!parts.userId) return null;
      return `profile_completed:${s(parts.userId)}`;
    case 'place_liked': {
      // One per venue ever — an unlike/relike cycle can't re-mint.
      const venue = parts.globalPlaceId || parts.placeId;
      if (!parts.userId || !venue) return null;
      return `place_liked:${s(parts.userId)}:${s(venue)}`;
    }
    case 'photo_liked': {
      // One per photo ever — unlike/relike can't re-mint. Photo ids are only
      // unique within their venue, so the venue leads the key.
      if (!parts.userId || !parts.globalPlaceId || !parts.photoId) return null;
      return `photo_liked:${s(parts.userId)}:${s(parts.globalPlaceId)}:${s(parts.photoId)}`;
    }
    case 'place_comment': {
      // First comment per venue — thread-padding pays nothing.
      const venue = parts.globalPlaceId || parts.placeId;
      if (!parts.userId || !venue) return null;
      return `place_comment:${s(parts.userId)}:${s(venue)}`;
    }
    case 'user_followed':
      // First follow of that person ever — unfollow/refollow can't re-mint.
      if (!parts.userId || !parts.followedUserId) return null;
      return `user_followed:${s(parts.userId)}:${s(parts.followedUserId)}`;
    case 'activity_reaction':
      // One per activity ever — swapping the emoji can't re-mint.
      if (!parts.userId || !parts.activityId) return null;
      return `activity_reaction:${s(parts.userId)}:${s(parts.activityId)}`;
    case 'moment_liked':
      // One per moment ever — unlike/relike can't re-mint.
      if (!parts.userId || !parts.videoId) return null;
      return `moment_liked:${s(parts.userId)}:${s(parts.videoId)}`;
    case 'moment_like_received':
      // Owner earns once per distinct liker per moment.
      if (!parts.userId || !parts.videoId || !parts.likerUserId) return null;
      return `moment_like_recv:${s(parts.userId)}:${s(parts.videoId)}:${s(parts.likerUserId)}`;
    case 'claim':
      // seq comes from bank.claimCount + 1, read inside the claim transaction:
      // two concurrent claims compute the same seq and the loser's create()
      // throws ALREADY_EXISTS — the second guard behind activeClaimId.
      if (!parts.userId || !parts.seq) return null;
      return `claim:${s(parts.userId)}:${parts.seq}`;
    default:
      return null;
  }
}

// Ledger entry factory. Append-only: reversals flip status, never the sign.
function createPiggyLedgerEntry({ userId, eventType, coins, sourceRef }) {
  const now = new Date();
  const clearAt = new Date(now.getTime() + piggyBankConfig.CLEARING_WINDOW_HOURS * 60 * 60 * 1000);
  return {
    userId,
    eventType,
    coins,
    status: 'pending',
    sourceRef: sourceRef || {},
    ruleVersion: piggyBankConfig.RULE_VERSION,
    createdAt: now.toISOString(),
    clearAt: clearAt.toISOString(),
    confirmedAt: null,
    reversedAt: null,
    reverseReason: null
  };
}

// Claim row factory. `coins` is the GROSS confirmed balance snapshotted at
// claim time (ledger never sign-flips); fee/net/cat math is frozen onto the
// row so a later config change can't reinterpret history. If COINS_PER_CAT
// ever exceeds 1, the indivisible remainder stays in confirmedCoins (the
// gross actually claimed is feeCoins + catAmount * COINS_PER_CAT).
function createPiggyClaimEntry({ userId, confirmedCoins, address }) {
  const claimCfg = piggyBankConfig.CLAIM;
  const feeCoins = claimCfg.CLAIM_FEE_COINS || 0;
  const catAmount = Math.floor((confirmedCoins - feeCoins) / claimCfg.COINS_PER_CAT);
  const coins = feeCoins + catAmount * claimCfg.COINS_PER_CAT;
  return {
    userId,
    eventType: 'claim',
    coins,
    feeCoins,
    netCoins: coins - feeCoins,
    catAmount,
    mojos: catAmount * claimCfg.MOJOS_PER_CAT,
    address,
    status: 'claim_pending',
    txId: null,
    attempts: 0,
    needsReview: false,
    failReason: null,
    ruleVersion: piggyBankConfig.RULE_VERSION,
    createdAt: new Date().toISOString(),
    sendingAt: null,
    sentAt: null,
    settledAt: null,
    failedAt: null,
    sourceRef: {}
  };
}

module.exports = {
  PIGGY_COLLECTIONS,
  PIGGY_EVENT_TYPES,
  PIGGY_STATUSES,
  sanitizeKeyPart,
  derivePiggyDedupKey,
  createPiggyLedgerEntry,
  createPiggyClaimEntry
};
