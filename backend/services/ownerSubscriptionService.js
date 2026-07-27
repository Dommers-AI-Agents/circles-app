// backend/services/ownerSubscriptionService.js
// FavCircles Business — the store-owner subscription, tracked separately from
// the consumer premium subscription (different StoreKit subscription group,
// dedicated owner* fields on the user doc). Free owner tier: claim the store,
// edit venue data, window QR (scan-to-save). Business tier: full stats
// dashboard, announcements, offers, and the loyalty program.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

const BUSINESS_PRODUCT_IDS = [
  'com.favcircles.circles.business.subscription.monthly',
  'com.favcircles.circles.business.subscription.annual'
];

const ACTIVE_STATUSES = ['active', 'trial', 'grace_period'];

const isBusinessProduct = (productId) =>
  BUSINESS_PRODUCT_IDS.includes(productId);

// Synchronous check over an already-loaded user object (req.user carries the
// full user doc). Super users and manually-flagged owners always pass.
const isOwnerPremiumUser = (user) => {
  if (!user) return false;
  if (user.isSuperUser === true) return true;
  if (user.ownerManuallyVerified === true) return true;
  if (!ACTIVE_STATUSES.includes(user.ownerSubscriptionStatus)) return false;
  const expiry = user.ownerSubscriptionExpiryDate
    ? new Date(user.ownerSubscriptionExpiryDate)
    : null;
  return !expiry || expiry > new Date();
};

// Per-instance cache of the last KNOWN owner-premium result (true OR false),
// so a transient Firestore error at the register falls back to the last known
// answer for that owner rather than blanket-approving every venue. Refreshed
// on every successful lookup; only consulted on error.
const premiumCache = new Map(); // userId -> { value: boolean, at: epochMs }

// Async variant for callers that only hold a user id (e.g. checking a venue
// owner's status during a customer's register scan). Fails to last-known on a
// Firestore error (defaulting to false when the owner has never been seen) —
// never blanket-true, which used to leak the paid program to lapsed venues.
const isOwnerPremiumById = async (userId) => {
  if (!userId) return false;
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const value = userDoc.exists && isOwnerPremiumUser(userDoc.data());
    premiumCache.set(userId, { value, at: Date.now() });
    return value;
  } catch (error) {
    const cached = premiumCache.get(userId);
    if (cached) {
      const ageSec = Math.round((Date.now() - cached.at) / 1000);
      console.warn(`[loyalty-integrity] owner-premium lookup failed for ${userId}; using last-known=${cached.value} (age ${ageSec}s): ${error.message}`);
      return cached.value;
    }
    console.warn(`[loyalty-integrity] owner-premium lookup failed for ${userId}; no cached value, denying: ${error.message}`);
    return false;
  }
};

// Explicit loyalty comp for a venue with no paying owner (hands-on pilot
// enrollments). Replaces the old implicit "unowned => live forever" rule.
// `loyaltyCompedUntil` is an ISO string or null (null = open-ended).
const isCompActive = (venue) => {
  if (!venue || venue.loyaltyComped !== true) return false;
  if (!venue.loyaltyCompedUntil) return true;
  return new Date(venue.loyaltyCompedUntil) > new Date();
};

// Whether a venue's loyalty program (register scans, offers, redemptions) is
// live, and WHY — the reason drives integrity logging at award time.
// reason ∈ 'comp' | 'owner_premium' | 'lapsed' | 'no_owner' | 'none'
const venueLoyaltyStatus = async (venue) => {
  if (!venue) return { active: false, reason: 'none' };
  if (isCompActive(venue)) return { active: true, reason: 'comp' };
  if (!venue.ownerUserId) return { active: false, reason: 'no_owner' };
  const premium = await isOwnerPremiumById(venue.ownerUserId);
  return { active: premium, reason: premium ? 'owner_premium' : 'lapsed' };
};

const isVenueLoyaltyActive = async (venue) => (await venueLoyaltyStatus(venue)).active;

module.exports = {
  BUSINESS_PRODUCT_IDS,
  isBusinessProduct,
  isOwnerPremiumUser,
  isOwnerPremiumById,
  isCompActive,
  venueLoyaltyStatus,
  isVenueLoyaltyActive
};
