// backend/services/rewardVoucherService.js
// Reward tickets (Wes, 2026-11-01): redeeming an offer spends the points and
// opens a 15-minute ticket the customer shows at the counter. Staff tap
// "Given" on the customer's phone; a ticket that runs out without that is
// expired and its points go back to the customer's balance at that store.
// Both sides see the history: the customer in Store Rewards, the store team
// in Manage Store → Rewards used.
//
// rewardVouchers/{voucherId} (voucherId = the redemption event's id) =
//   { userId, venueId, venueName, offerId, offerTitle, pointsCost, voucherCode,
//     createdAt, expiresAt, status: 'issued'|'given'|'expired', givenAt,
//     expiredAt, refunded }

const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS, sanitizeKeyPart, createRewardEvent } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');

const VOUCHERS = 'rewardVouchers';
/// Staff can still tap "Given" this long after the countdown ends (a slow
/// handover at the counter); the refund waits for it
const GRACE_MS = 2 * 60 * 1000;

const db = () => getFirestore();
const voucherRef = (voucherId) => db().collection(VOUCHERS).doc(String(voucherId));

function newVoucher({ voucherId, userId, venueId, venueName, offer, voucherCode, expiresAt, now = new Date() }) {
  return {
    voucherId, userId, venueId, venueName: venueName || null,
    offerId: offer.offerId, offerTitle: offer.title, pointsCost: offer.pointsCost,
    voucherCode, createdAt: now.toISOString(), expiresAt, status: 'issued'
  };
}

/// What a ticket is right now: an issued ticket past its time (plus grace)
/// reads as expired even before the sweep refunds it. Pure.
function effectiveStatus(voucher, now = Date.now()) {
  if (voucher.status !== 'issued') return voucher.status;
  return new Date(voucher.expiresAt).getTime() + GRACE_MS < now ? 'expired' : 'issued';
}

const publicVoucher = (voucher, now = Date.now()) => ({
  voucherId: voucher.voucherId,
  venueId: voucher.venueId,
  venueName: voucher.venueName,
  offerTitle: voucher.offerTitle,
  pointsCost: voucher.pointsCost,
  voucherCode: voucher.voucherCode,
  createdAt: voucher.createdAt,
  expiresAt: voucher.expiresAt,
  status: effectiveStatus(voucher, now),
  givenAt: voucher.givenAt || null,
  refunded: voucher.pointsCost !== 0 && (voucher.refunded === true || effectiveStatus(voucher, now) === 'expired'),
  // A coupon's ticket (services/storeCoupons): its online code for the store's own site
  ...(voucher.couponId ? { couponId: voucher.couponId, onlineCode: voucher.onlineCode || null } : {})
});

/// Staff tapped "Given" on the customer's phone
async function markGiven(userId, voucherId, now = Date.now()) {
  const ref = voucherRef(voucherId);
  const result = await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists || doc.data().userId !== userId) throw new ServiceError(404, 'VOUCHER_NOT_FOUND', 'That reward wasn’t found');
    const voucher = doc.data();
    if (voucher.status === 'given') return { voucher, already: true };
    if (effectiveStatus(voucher, now) !== 'issued') {
      throw new ServiceError(409, 'VOUCHER_EXPIRED', 'This reward ran out before it was given. Your points are back.');
    }
    const givenAt = new Date(now).toISOString();
    tx.update(ref, { status: 'given', givenAt });
    tx.update(db().collection(STICKER_COLLECTIONS.REWARD_EVENTS).doc(voucherId), { status: 'given', givenAt });
    return { voucher: { ...voucher, status: 'given', givenAt }, already: false };
  });
  if (!result.already) {
    require('./rewardService').incrementVenueStats(result.voucher.venueId, 'rewardsGiven');
    // A coupon ticket given = the coupon used (services/storeCoupons)
    await require('./storeCoupons').onTicketGiven(result.voucher, new Date(now)).catch((e) => console.warn('coupon given hook:', e.message));
  }
  return publicVoucher(result.voucher, now);
}

/// One ticket past its time: expired, and its points go back. Idempotent
/// (the status check runs inside the transaction).
async function expireOne(voucherId, now = Date.now()) {
  const ref = voucherRef(voucherId);
  const refunded = await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return null;
    const voucher = doc.data();
    if (voucher.status !== 'issued' || effectiveStatus(voucher, now) !== 'expired') return null;
    const at = new Date(now).toISOString();
    tx.update(ref, { status: 'expired', expiredAt: at, refunded: voucher.pointsCost !== 0 });
    tx.update(db().collection(STICKER_COLLECTIONS.REWARD_EVENTS).doc(voucherId), { status: 'expired' });
    // A coupon's ticket cost no points: nothing to give back (the coupon
    // itself goes back to claimed, below)
    if (voucher.pointsCost === 0) return voucher;
    tx.update(db().collection(COLLECTIONS.USERS).doc(voucher.userId), {
      rewardPoints: FieldValue.increment(voucher.pointsCost),
      [`rewardPointsByVenue.${voucher.venueId}.points`]: FieldValue.increment(voucher.pointsCost)
    });
    // The customer's history shows the points coming back
    tx.set(db().collection(STICKER_COLLECTIONS.REWARD_EVENTS).doc(sanitizeKeyPart(`refund:${voucherId}`)), createRewardEvent({
      userId: voucher.userId, type: 'redemption_refund', points: voucher.pointsCost,
      venueId: voucher.venueId, venueName: voucher.venueName, offerId: voucher.offerId,
      offerTitle: voucher.offerTitle, voucherCode: voucher.voucherCode
    }));
    return voucher;
  });
  if (refunded) {
    const rewardService = require('./rewardService');
    rewardService.incrementVenueStats(refunded.venueId, 'rewardsExpired');
    if (refunded.couponClaimId) {
      await require('./storeCoupons').onTicketExpired({ ...refunded, voucherId }).catch((e) => console.warn('coupon expiry hook:', e.message));
    }
    rewardService.walletBalanceChanged(refunded.userId, refunded.venueId);
  }
  return !!refunded;
}

/// Every ticket past its time, everyone's (the sweep task)
async function expireDue(now = Date.now(), { limit = 200 } = {}) {
  const cutoff = new Date(now - GRACE_MS).toISOString();
  const snap = await db().collection(VOUCHERS).where('status', '==', 'issued').where('expiresAt', '<', cutoff).limit(limit).get();
  let expired = 0;
  for (const doc of snap.docs) {
    if (await expireOne(doc.id, now)) expired += 1;
  }
  return { checked: snap.size, expired };
}

/// The customer's open tickets and recent history; their own past-time
/// tickets are refunded on the way, so the points are right immediately
async function listForUser(userId, now = Date.now()) {
  const open = await db().collection(VOUCHERS).where('userId', '==', userId).where('status', '==', 'issued').get();
  for (const doc of open.docs) {
    if (effectiveStatus(doc.data(), now) === 'expired') await expireOne(doc.id, now);
  }
  const recent = await db().collection(VOUCHERS).where('userId', '==', userId).orderBy('createdAt', 'desc').limit(20).get();
  const vouchers = recent.docs.map((d) => publicVoucher({ voucherId: d.id, ...d.data() }, now));
  return { active: vouchers.filter((v) => v.status === 'issued'), recent: vouchers };
}

/// The store team's "Rewards used": newest first, with the customer's name
async function listForVenue(venueId, now = Date.now()) {
  const snap = await db().collection(VOUCHERS).where('venueId', '==', venueId).orderBy('createdAt', 'desc').limit(50).get();
  const userIds = [...new Set(snap.docs.map((d) => d.data().userId))];
  const names = new Map();
  await Promise.all(userIds.map(async (id) => {
    const user = await db().collection(COLLECTIONS.USERS).doc(id).get().catch(() => null);
    const data = user && user.exists ? user.data() : {};
    names.set(id, data.displayName || data.name || 'A customer');
  }));
  return snap.docs.map((d) => {
    const voucher = { voucherId: d.id, ...d.data() };
    return { ...publicVoucher(voucher, now), customerName: names.get(voucher.userId) || 'A customer' };
  });
}

module.exports = { VOUCHERS, GRACE_MS, voucherRef, newVoucher, effectiveStatus, publicVoucher, markGiven, expireOne, expireDue, listForUser, listForVenue };
