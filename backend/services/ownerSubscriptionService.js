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

// Async variant for callers that only hold a user id (e.g. checking a venue
// owner's status during a customer's register scan).
const isOwnerPremiumById = async (userId) => {
  if (!userId) return false;
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    return userDoc.exists && isOwnerPremiumUser(userDoc.data());
  } catch (error) {
    console.error('⚠️ Owner premium lookup failed:', error.message);
    // Fail open for the loyalty path: a Firestore hiccup shouldn't zero out a
    // paying store's rewards at the register
    return true;
  }
};

// Whether a venue's loyalty program (register scans, offers, redemptions) is
// live. Unowned/legacy venues stay live — they were enrolled hands-on and
// gating them would silently break stickers already in the field.
const isVenueLoyaltyActive = async (venue) => {
  if (!venue) return false;
  if (!venue.ownerUserId) return true;
  return isOwnerPremiumById(venue.ownerUserId);
};

module.exports = {
  BUSINESS_PRODUCT_IDS,
  isBusinessProduct,
  isOwnerPremiumUser,
  isOwnerPremiumById,
  isVenueLoyaltyActive
};
