// backend/services/storeReferrals.js
//
// Bring a friend (Wes, 2026-11-09): a store's customers invite friends with
// the store's own window link plus `?ref=<their id>`; when the friend's
// FIRST purchase is scanned at the register, both earn the points the owner
// set. Business only; honor-system points like the rest of rewards.
//
//   stickerVenues.referrals = { enabled, referrerPoints, friendPoints, couponId? }
//     couponId (2026-11-14): one of the store's coupons (services/storeCoupons)
//     rides on the invite link as &c=, so the friend's first scan claims it too
//   users/{friend}.rewardPointsByVenue.{venue}.referredBy = <referrer id>   (set by the window scan)
//   users/{referrer}.rewardPointsByVenue.{venue}.referralsByMonth.{YYYY-MM}  (the cap, no index)
//   rewardEvents type 'referral', role 'referrer' | 'friend', sourceUserId = the other person
//
// Blocked: inviting yourself, a friend who already earned at the store, and
// more than 20 rewarded referrals per person per store per month.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS, validateBonusPoints } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');

const DEFAULTS = Object.freeze({ enabled: false, referrerPoints: 50, friendPoints: 25, couponId: null });
const MONTHLY_CAP = 20;
const db = () => getFirestore();
const field = (venueId, name) => `rewardPointsByVenue.${venueId}.${name}`;
const monthKey = (now = new Date()) => now.toISOString().slice(0, 7);

// ---------- Settings ----------

const settingsOf = (venue) => {
  const r = (venue && venue.referrals) || {};
  const points = (v, fallback) => (Number.isInteger(v) && v >= 0 ? v : fallback);
  return {
    enabled: r.enabled === true,
    referrerPoints: points(r.referrerPoints, DEFAULTS.referrerPoints),
    friendPoints: points(r.friendPoints, DEFAULTS.friendPoints),
    couponId: typeof r.couponId === 'string' && r.couponId ? r.couponId : null
  };
};

const normalizeSettings = (input = {}) => {
  if (input.enabled !== undefined && typeof input.enabled !== 'boolean') {
    throw new ServiceError(400, 'invalid_referrals', 'Bring a friend must be on or off.');
  }
  const points = (v, name, fallback) => {
    const n = v === undefined ? fallback : Number(v);
    const errors = validateBonusPoints(n, name);
    if (errors.length) throw new ServiceError(400, 'invalid_referrals', errors[0]);
    return n;
  };
  let couponId = null;
  if (input.couponId !== undefined && input.couponId !== null && input.couponId !== '') {
    couponId = require('./storeCoupons').normalizeId(input.couponId);
    if (!couponId) throw new ServiceError(400, 'invalid_referrals', 'Pick one of your coupons for the friend.');
  }
  return {
    enabled: input.enabled === true,
    referrerPoints: points(input.referrerPoints, 'Points for the friend who invites', DEFAULTS.referrerPoints),
    friendPoints: points(input.friendPoints, 'Points for the new customer', DEFAULTS.friendPoints),
    couponId
  };
};

/** The store's own window link with the inviter on it. */
const inviteUrl = (venue, userId, { now = new Date() } = {}) => {
  if (!venue || !venue.windowCode || !userId) return null;
  const coupon = friendCoupon(venue, now);
  return `${require('./rewardService').stickerUrl(venue.windowCode)}?ref=${encodeURIComponent(String(userId))}${coupon ? `&c=${coupon.couponId}` : ''}`;
};

/** The coupon the friend gets on the link, while the store still offers it. */
const friendCoupon = (venue, now = new Date()) => {
  const s = settingsOf(venue);
  if (!s.couponId) return null;
  const coupons = require('./storeCoupons');
  const coupon = coupons.findCoupon(venue, s.couponId);
  if (!coupon || coupons.claimVerdict({ coupon, counts: coupons.countsOf(venue, coupon.couponId), now }) !== 'ok') return null;
  return coupons.publicCoupon(coupon);
};

/** What a customer sees on the store's page: the offer and their link; null while off or the plan isn't live. */
const publicReferral = (venue, userId, { live, now = new Date() }) => {
  const s = settingsOf(venue);
  if (!live || !s.enabled) return null;
  return { enabled: true, referrerPoints: s.referrerPoints, friendPoints: s.friendPoints, inviteUrl: inviteUrl(venue, userId, { now }), friendCoupon: friendCoupon(venue, now) };
};

// ---------- The two moments ----------

/**
 * The friend arrived through someone's link (a window scan with `ref`):
 * remember who, on the friend's bucket, if they never earned here before.
 * Pure decision in `shouldRemember`; this does the write.
 */
const shouldRemember = ({ settings, live, refUserId, newUserId, bucket }) => {
  if (!live || !settings.enabled) return false;
  if (!refUserId || !newUserId || String(refUserId) === String(newUserId)) return false;
  if (bucket && (bucket.purchases || 0) > 0) return false; // already a customer
  if (bucket && bucket.referredBy) return false;            // already spoken for
  return true;
};

async function remember({ venue, refUserId, newUserId, live, now = new Date() }) {
  const settings = settingsOf(venue);
  const userRef = db().collection(COLLECTIONS.USERS).doc(String(newUserId));
  const doc = await userRef.get();
  const bucket = ((doc.exists && doc.data().rewardPointsByVenue) || {})[venue.venueId] || null;
  if (!shouldRemember({ settings, live, refUserId, newUserId, bucket })) return { remembered: false };
  const refDoc = await db().collection(COLLECTIONS.USERS).doc(String(refUserId)).get();
  if (!refDoc.exists) return { remembered: false };
  await userRef.update(field(venue.venueId, 'referredBy'), String(refUserId), field(venue.venueId, 'referredAt'), now.toISOString());
  return { remembered: true };
};

/**
 * The friend's first purchase was scanned: pay both. `bucketBefore` is the
 * friend's bucket as it was before the visit award. Idempotent per friend
 * per store; the referrer's monthly cap is a counter on their bucket.
 */
async function creditOnVisit({ venue, friendUserId, bucketBefore, now = new Date() }) {
  const settings = settingsOf(venue);
  if (!settings.enabled) return { credited: false, reason: 'off' };
  const refUserId = bucketBefore && bucketBefore.referredBy;
  if (!refUserId || (bucketBefore.purchases || 0) > 0 || bucketBefore.referralPaidAt) return { credited: false, reason: 'not_first' };
  if (String(refUserId) === String(friendUserId)) return { credited: false, reason: 'self' };

  const refDoc = await db().collection(COLLECTIONS.USERS).doc(String(refUserId)).get();
  if (!refDoc.exists) return { credited: false, reason: 'no_referrer' };
  const refBucket = ((refDoc.data().rewardPointsByVenue) || {})[venue.venueId] || {};
  const month = monthKey(now);
  const soFar = ((refBucket.referralsByMonth || {})[month]) || 0;
  if (soFar >= MONTHLY_CAP) return { credited: false, reason: 'capped' };

  const rewardService = require('./rewardService');
  const base = { venueId: venue.venueId, venueName: venue.venueName, googlePlaceId: venue.googlePlaceId };
  const friend = await rewardService.awardPoints({
    ...base, userId: String(friendUserId), type: 'referral', role: 'friend', points: settings.friendPoints,
    sourceUserId: String(refUserId), idempotencyKey: `referral:${venue.venueId}:${friendUserId}`,
    bucketUpdate: { referralPaidAt: now.toISOString() }
  });
  if (!friend.awarded) return { credited: false, reason: 'duplicate' };
  await rewardService.awardPoints({
    ...base, userId: String(refUserId), type: 'referral', role: 'referrer', points: settings.referrerPoints,
    sourceUserId: String(friendUserId), idempotencyKey: `referral:${venue.venueId}:${friendUserId}:referrer`,
    bucketUpdate: { [`referralsByMonth.${month}`]: FieldValue.increment(1) }
  });

  const friendName = await displayName(friendUserId);
  const refName = await displayName(refUserId);
  const store = venue.venueName || 'the store';
  const { venueGlobalPlaceId } = require('./venueHelpers');
  const placeId = await venueGlobalPlaceId(venue).catch(() => null);
  const notify = require('./notifyQuiet').sendInBackground;
  notify(String(refUserId), {
    type: 'store_nudge', title: `${friendName} made their first visit to ${store}`,
    body: `+${settings.referrerPoints} points for bringing a friend.`, data: { venueId: venue.venueId, placeId }
  }, 'referral');
  notify(String(friendUserId), {
    type: 'store_nudge', title: `+${settings.friendPoints} bonus points at ${store}`,
    body: `${refName} invited you — thanks for coming in.`, data: { venueId: venue.venueId, placeId }
  }, 'referral');
  return { credited: true, referrerPoints: settings.referrerPoints, friendPoints: settings.friendPoints, refUserId: String(refUserId) };
}

async function displayName(userId) {
  const doc = await db().collection(COLLECTIONS.USERS).doc(String(userId)).get().catch(() => null);
  return (doc && doc.exists && (doc.data().firstName || doc.data().displayName)) || 'A friend';
}

// ---------- The owner's view ----------

/** How many friends were brought in, all time and this month. */
async function stats(venue) {
  const snap = await db().collection(STICKER_COLLECTIONS.REWARD_EVENTS)
    .where('venueId', '==', venue.venueId).where('type', '==', 'referral').get();
  const rows = snap.docs.map((d) => d.data()).filter((e) => e.role === 'referrer');
  const month = monthKey();
  return {
    friendsBrought: rows.length,
    thisMonth: rows.filter((e) => String(e.createdAt || '').startsWith(month)).length,
    pointsPaid: snap.docs.reduce((sum, d) => sum + (d.data().points || 0), 0)
  };
}

async function saveSettings(venue, input) {
  const settings = normalizeSettings(input);
  await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId).update({ referrals: settings });
  return settings;
}

module.exports = { DEFAULTS, MONTHLY_CAP, settingsOf, normalizeSettings, inviteUrl, friendCoupon, publicReferral, shouldRemember, remember, creditOnVisit, stats, saveSettings };
