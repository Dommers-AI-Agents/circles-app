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
  'suggestion_posted'
];

const PIGGY_STATUSES = ['pending', 'confirmed', 'reversed', 'held'];

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
      const venue = parts.globalPlaceId || parts.placeId;
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

module.exports = {
  PIGGY_COLLECTIONS,
  PIGGY_EVENT_TYPES,
  PIGGY_STATUSES,
  sanitizeKeyPart,
  derivePiggyDedupKey,
  createPiggyLedgerEntry
};
