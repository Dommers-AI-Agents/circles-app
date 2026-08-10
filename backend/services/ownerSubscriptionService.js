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

// Paid subscription active on the account (ignores super/manual bypasses and
// says nothing about WHICH venue it covers).
const hasActiveOwnerSubscription = (user) => {
  if (!user) return false;
  if (!ACTIVE_STATUSES.includes(user.ownerSubscriptionStatus)) return false;
  const expiry = user.ownerSubscriptionExpiryDate
    ? new Date(user.ownerSubscriptionExpiryDate)
    : null;
  return !expiry || expiry > new Date();
};

// Account-level "has any business entitlement" (profile/UI summary only —
// venue gating must use isOwnerPremiumForVenue). Super users and
// manually-flagged owners always pass.
const isOwnerPremiumUser = (user) => {
  if (!user) return false;
  if (user.isSuperUser === true) return true;
  if (user.ownerManuallyVerified === true) return true;
  return hasActiveOwnerSubscription(user);
};

// The Business subscription covers exactly ONE venue (ownerSubscriptionVenueId,
// stamped at purchase) — an owner with several stores subscribes per store.
// Super users and manually-verified owners keep account-wide access; those are
// admin grants, not App Store purchases.
//
// Exception: the account's own ONLINE STORE (virtual venue) rides the same
// subscription. A virtual venue IS the account (one per account), so the
// per-venue binding that stops premium hopping between physical stores
// doesn't apply. Callers always pass the venue OWNER's user doc, so
// ownership is already established; pass the venue doc to enable this.
const isOwnerPremiumForVenue = (user, venueId, venue = null) => {
  if (!user || !venueId) return false;
  if (user.isSuperUser === true) return true;
  if (user.ownerManuallyVerified === true) return true;
  if (!hasActiveOwnerSubscription(user)) return false;
  if (user.ownerSubscriptionVenueId === venueId) return true;
  return venue ? venue.isVirtual === true : false;
};

// Per-instance cache of the last KNOWN owner-premium result (true OR false),
// so a transient Firestore error at the register falls back to the last known
// answer for that owner+venue rather than blanket-approving every venue.
// Refreshed on every successful lookup; only consulted on error.
const premiumCache = new Map(); // `${userId}:${venueId}` -> { value, at: epochMs }

// Async variant for callers that only hold ids (e.g. checking a venue owner's
// status during a customer's register scan). Fails to last-known on a
// Firestore error (defaulting to false when the pair has never been seen) —
// never blanket-true, which used to leak the paid program to lapsed venues.
const isOwnerPremiumById = async (userId, venueId, venue = null) => {
  if (!userId || !venueId) return false;
  const cacheKey = `${userId}:${venueId}`;
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const value = userDoc.exists && isOwnerPremiumForVenue(userDoc.data(), venueId, venue);
    premiumCache.set(cacheKey, { value, at: Date.now() });
    return value;
  } catch (error) {
    const cached = premiumCache.get(cacheKey);
    if (cached) {
      const ageSec = Math.round((Date.now() - cached.at) / 1000);
      console.warn(`[loyalty-integrity] owner-premium lookup failed for ${cacheKey}; using last-known=${cached.value} (age ${ageSec}s): ${error.message}`);
      return cached.value;
    }
    console.warn(`[loyalty-integrity] owner-premium lookup failed for ${cacheKey}; no cached value, denying: ${error.message}`);
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
  const premium = await isOwnerPremiumById(venue.ownerUserId, venue.venueId || venue.id, venue);
  return { active: premium, reason: premium ? 'owner_premium' : 'lapsed' };
};

const isVenueLoyaltyActive = async (venue) => (await venueLoyaltyStatus(venue)).active;

module.exports = {
  BUSINESS_PRODUCT_IDS,
  isBusinessProduct,
  isOwnerPremiumUser,
  isOwnerPremiumForVenue,
  isOwnerPremiumById,
  isCompActive,
  venueLoyaltyStatus,
  isVenueLoyaltyActive
};
