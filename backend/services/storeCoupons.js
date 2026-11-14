// backend/services/storeCoupons.js
//
// Coupons (Wes, 2026-11-14, a pizzeria's mailer on a friend's fridge: "he
// often forgets it at home"). A store writes a coupon — "20% off any pickup
// order", good until a date — and puts its QR on the mailer, the flyer, the
// bag. The QR is the store's own window link plus `?c=<couponId>`, so a scan
// does everything a window scan does (the App Clip saves the store and signs
// them in) and then CLAIMS the coupon for that account: it lives on the
// store's Wallet card and in Store Rewards, where it can't be forgotten.
//
// At the counter the register scan turns a claimed coupon into the same
// 15-minute ticket a points reward gets (services/rewardVoucherService):
// staff tap "Given" on the customer's phone, or the ticket runs out and the
// coupon goes back to claimed. A coupon with an online code shows the code
// too, for the store's own ordering site. Business only; honor system like
// the rest of rewards.
//
//   stickerVenues.coupons[]            { couponId, title, detail, onlineCode, campaign,
//                                        expiresAt, maxClaims, active, createdAt, updatedAt }
//   stickerVenues.couponCounts.{id}    { scans, claims, tickets, redemptions, newCustomers }
//   couponClaims/{venue}_{uid}_{id}    { venueId, userId, couponId, title, campaign, onlineCode,
//                                        expiresAt, claimedAt, via, newCustomer,
//                                        status: claimed | ticket | used, voucherId, ticketAt, usedAt }
//   rewardEvents (type coupon_redemption, 0 points) + rewardVouchers, per ticket
//
// One claim per account per coupon (the claim doc is created once). Claims
// are never pruned: they are the campaign's record (memory: never-prune-user-data).
const crypto = require('crypto');
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS, sanitizeKeyPart, createRewardEvent } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const rewardConfig = require('../config/rewardConfig');

const CLAIMS = 'couponClaims';
const MAX_COUPONS = 20;
const MAX_TITLE = 60;
const MAX_DETAIL = 200;
const MAX_CAMPAIGN = 60;
const MAX_ONLINE_CODE = 32;
const MAX_LIFETIME_DAYS = 366;
const MAX_CLAIMS = 100000;
const DAY_MS = 24 * 60 * 60 * 1000;
// No 0/O, 1/I/L: a code someone reads off a flyer
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const ID_LENGTH = 6;
const ID_RE = /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/;
const EVENT_TYPE = 'coupon_redemption';

const db = () => getFirestore();
const venueRef = (venueId) => db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId));
const claimId = (venueId, userId, couponId) => sanitizeKeyPart(`${venueId}_${userId}_${couponId}`);
const claimRef = (id) => db().collection(CLAIMS).doc(id);
const iso = (d) => new Date(d).toISOString();

function newCouponId() {
  let id = '';
  for (let i = 0; i < ID_LENGTH; i += 1) id += ALPHABET[crypto.randomInt(ALPHABET.length)];
  return id;
}

/** A coupon id as scanned or typed → canonical, or null. Pure. */
const normalizeId = (raw) => {
  const upper = String(raw || '').trim().toUpperCase();
  return ID_RE.test(upper) ? upper : null;
};

// ---------- The coupon (pure) ----------

const clean = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

/**
 * The owner's coupon, checked. `existing` for an edit (fields left out keep
 * their value). Refuses with 400 invalid_coupon.
 */
function normalizeCoupon(input = {}, { now = new Date(), existing = null } = {}) {
  const body = input && typeof input === 'object' ? input : {};
  // A finished coupon may still be paused or renamed: the date is checked
  // when it is set, not every time the owner touches the coupon
  const dateChanged = !existing || body.expiresAt !== undefined;
  const pick = (key, fallback) => (body[key] === undefined ? (existing ? existing[key] : fallback) : body[key]);

  const title = clean(pick('title', ''), MAX_TITLE);
  if (!title) throw new ServiceError(400, 'invalid_coupon', 'Say what the coupon gives, like "20% off any pickup order".');
  if (String(pick('title', '')).trim().length > MAX_TITLE) throw new ServiceError(400, 'invalid_coupon', `Keep the coupon to ${MAX_TITLE} characters.`);

  const detailRaw = pick('detail', '');
  const detail = detailRaw === null ? '' : clean(detailRaw, MAX_DETAIL);
  if (detailRaw && String(detailRaw).trim().length > MAX_DETAIL) throw new ServiceError(400, 'invalid_coupon', `Keep the fine print to ${MAX_DETAIL} characters.`);

  const campaignRaw = pick('campaign', '');
  const campaign = campaignRaw === null ? '' : clean(campaignRaw, MAX_CAMPAIGN);

  const codeRaw = pick('onlineCode', '');
  const onlineCode = codeRaw === null ? '' : String(codeRaw).trim().toUpperCase().slice(0, MAX_ONLINE_CODE);
  if (onlineCode && !/^[A-Z0-9][A-Z0-9_-]*$/.test(onlineCode)) {
    throw new ServiceError(400, 'invalid_coupon', 'An online code is letters and numbers, like TGOSTVQC.');
  }

  const expiresRaw = pick('expiresAt', null);
  const expiresMs = Date.parse(expiresRaw);
  if (!expiresRaw || Number.isNaN(expiresMs)) throw new ServiceError(400, 'invalid_coupon', 'Pick the day the coupon ends.');
  if (dateChanged && expiresMs <= now.getTime()) throw new ServiceError(400, 'invalid_coupon', 'The end date has already passed.');
  if (dateChanged && expiresMs > now.getTime() + MAX_LIFETIME_DAYS * DAY_MS) throw new ServiceError(400, 'invalid_coupon', 'A coupon runs for at most a year.');

  const maxRaw = pick('maxClaims', null);
  let maxClaims = null;
  if (maxRaw !== null && maxRaw !== undefined && maxRaw !== '') {
    maxClaims = Number(maxRaw);
    if (!Number.isInteger(maxClaims) || maxClaims < 1 || maxClaims > MAX_CLAIMS) {
      throw new ServiceError(400, 'invalid_coupon', `How many may claim it: a whole number up to ${MAX_CLAIMS}, or leave it open.`);
    }
  }

  const activeRaw = pick('active', true);
  if (typeof activeRaw !== 'boolean') throw new ServiceError(400, 'invalid_coupon', 'A coupon is on or off.');

  return {
    title, detail: detail || null, campaign: campaign || null, onlineCode: onlineCode || null,
    expiresAt: iso(expiresMs), maxClaims, active: activeRaw
  };
}

const isExpired = (coupon, now = new Date()) => !coupon || !coupon.expiresAt || Date.parse(coupon.expiresAt) <= now.getTime();

const countsOf = (venue, couponId) => {
  const c = ((venue && venue.couponCounts) || {})[couponId] || {};
  return {
    scans: c.scans || 0, claims: c.claims || 0, tickets: c.tickets || 0,
    redemptions: c.redemptions || 0, newCustomers: c.newCustomers || 0
  };
};

/**
 * May this person claim this coupon now? Pure.
 * @returns {'ok'|'not_found'|'paused'|'expired'|'full'|'already'}
 */
function claimVerdict({ coupon, existing = null, counts = {}, now = new Date() }) {
  if (!coupon) return 'not_found';
  if (existing) return 'already';
  if (coupon.active === false) return 'paused';
  if (isExpired(coupon, now)) return 'expired';
  if (Number.isInteger(coupon.maxClaims) && (counts.claims || 0) >= coupon.maxClaims) return 'full';
  return 'ok';
}

/** What the owner sees per coupon: the coupon, its link, how it's doing. Pure. */
function ownerCoupon(venue, coupon, now = new Date()) {
  const counts = countsOf(venue, coupon.couponId);
  const expired = isExpired(coupon, now);
  const full = Number.isInteger(coupon.maxClaims) && counts.claims >= coupon.maxClaims;
  return {
    ...coupon,
    url: couponUrl(venue, coupon.couponId),
    counts,
    state: coupon.active === false ? 'paused' : (expired ? 'ended' : (full ? 'full' : 'live'))
  };
}

/** The store's window link with the coupon on it (the QR on the flyer). */
const couponUrl = (venue, couponId) => {
  if (!venue || !venue.windowCode || !couponId) return null;
  return `${require('./rewardService').stickerUrl(venue.windowCode)}?c=${encodeURIComponent(couponId)}`;
};

/** A coupon as the customer sees it (on a claim, a card, a scan). Pure. */
const publicCoupon = (coupon) => (coupon ? {
  couponId: coupon.couponId,
  title: coupon.title,
  detail: coupon.detail || null,
  onlineCode: coupon.onlineCode || null,
  expiresAt: coupon.expiresAt || null
} : null);

/** A claim as the customer sees it; a past-date coupon reads as expired. Pure. */
function claimView(claim, now = new Date()) {
  if (!claim) return null;
  const expired = claim.status !== 'used' && isExpired(claim, now);
  return {
    claimId: claim.claimId,
    venueId: claim.venueId,
    venueName: claim.venueName || null,
    couponId: claim.couponId,
    title: claim.title,
    detail: claim.detail || null,
    onlineCode: claim.onlineCode || null,
    campaign: claim.campaign || null,
    expiresAt: claim.expiresAt || null,
    claimedAt: claim.claimedAt || null,
    status: expired ? 'expired' : claim.status,
    voucherId: claim.status === 'ticket' ? (claim.voucherId || null) : null,
    usedAt: claim.usedAt || null
  };
}

const isOpen = (claim, now = new Date()) => !!claim && (claim.status === 'claimed' || claim.status === 'ticket') && !isExpired(claim, now);

// ---------- The owner's side ----------

const liveCoupons = (venue) => (Array.isArray(venue && venue.coupons) ? venue.coupons : []);
const findCoupon = (venue, couponId) => liveCoupons(venue).find((c) => c.couponId === couponId) || null;

/** The owner's list, newest first. */
const listForOwner = (venue, now = new Date()) =>
  [...liveCoupons(venue)].sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')))
    .map((c) => ownerCoupon(venue, c, now));

async function create(venue, input, { now = new Date() } = {}) {
  const coupons = liveCoupons(venue);
  if (coupons.length >= MAX_COUPONS) {
    throw new ServiceError(400, 'too_many_coupons', `A store keeps up to ${MAX_COUPONS} coupons. Delete an old one first.`);
  }
  const fields = normalizeCoupon(input, { now });
  let couponId = newCouponId();
  while (coupons.some((c) => c.couponId === couponId)) couponId = newCouponId();
  const coupon = { couponId, ...fields, createdAt: now.toISOString(), updatedAt: now.toISOString() };
  const next = [...coupons, coupon];
  await venueRef(venue.venueId).update({ coupons: next, updatedAt: now.toISOString() });
  const after = { ...venue, coupons: next };
  return { coupon: ownerCoupon(after, coupon, now), coupons: listForOwner(after, now) };
}

async function update(venue, couponId, input, { now = new Date() } = {}) {
  const coupons = liveCoupons(venue);
  const index = coupons.findIndex((c) => c.couponId === couponId);
  if (index < 0) throw new ServiceError(404, 'coupon_not_found', 'That coupon isn’t here anymore.');
  const existing = coupons[index];
  const fields = normalizeCoupon(input, { now, existing });
  const coupon = { ...existing, ...fields, updatedAt: now.toISOString() };
  const next = [...coupons];
  next[index] = coupon;
  await venueRef(venue.venueId).update({ coupons: next, updatedAt: now.toISOString() });
  const after = { ...venue, coupons: next };
  return { coupon: ownerCoupon(after, coupon, now), coupons: listForOwner(after, now) };
}

async function remove(venue, couponId, { now = new Date() } = {}) {
  const coupons = liveCoupons(venue);
  if (!coupons.some((c) => c.couponId === couponId)) throw new ServiceError(404, 'coupon_not_found', 'That coupon isn’t here anymore.');
  const next = coupons.filter((c) => c.couponId !== couponId);
  await venueRef(venue.venueId).update({ coupons: next, updatedAt: now.toISOString() });
  return { coupons: listForOwner({ ...venue, coupons: next }, now) };
}

const bump = (venueId, couponId, field, amount = 1) =>
  venueRef(venueId).update(`couponCounts.${couponId}.${field}`, FieldValue.increment(amount))
    .catch((error) => console.warn(`[coupons] count ${couponId}.${field}: ${error.message}`));

// ---------- Claiming (the scan) ----------

/**
 * What a scan with `?c=` does for `userId`: claims the coupon when it can.
 * Every scan of a live coupon counts, claimed or not. Returns the coupon the
 * scan should show plus `status`: claimed | already | expired | full |
 * paused | not_found.
 */
async function claim({ venue, couponId: rawId, userId, via = 'window_scan', now = new Date() }) {
  const couponId = normalizeId(rawId);
  const coupon = couponId ? findCoupon(venue, couponId) : null;
  if (!coupon) return { status: 'not_found', coupon: null, claim: null };
  bump(venue.venueId, couponId, 'scans');

  const id = claimId(venue.venueId, userId, couponId);
  const existingDoc = await claimRef(id).get();
  const existing = existingDoc.exists ? { claimId: id, ...existingDoc.data() } : null;
  const verdict = claimVerdict({ coupon, existing, counts: countsOf(venue, couponId), now });
  if (verdict !== 'ok') return { status: verdict, coupon: publicCoupon(coupon), claim: existing ? claimView(existing, now) : null };

  // Is this their first purchase here? The campaign's "new customers" is
  // measured when they claim, before the visit the coupon brings
  const userDoc = await db().collection(COLLECTIONS.USERS).doc(String(userId)).get();
  const bucket = ((userDoc.exists && userDoc.data().rewardPointsByVenue) || {})[venue.venueId] || {};
  const record = {
    claimId: id,
    venueId: venue.venueId,
    venueName: venue.venueName || venue.placeName || null,
    userId: String(userId),
    couponId,
    title: coupon.title,
    detail: coupon.detail || null,
    onlineCode: coupon.onlineCode || null,
    campaign: coupon.campaign || null,
    expiresAt: coupon.expiresAt,
    claimedAt: now.toISOString(),
    via,
    newCustomer: !(bucket.purchases > 0),
    status: 'claimed',
    voucherId: null
  };
  try {
    await claimRef(id).create(record);
  } catch (error) {
    if (error.code === 6 || /already exists/i.test(error.message || '')) {
      return { status: 'already', coupon: publicCoupon(coupon), claim: claimView(record, now) };
    }
    throw error;
  }
  await bump(venue.venueId, couponId, 'claims');
  require('./rewardService').walletBalanceChanged(String(userId), venue.venueId);
  return { status: 'claimed', coupon: publicCoupon(coupon), claim: claimView(record, now) };
}

/** The coupon a scan link names, before anyone signs in (the App Clip's preview). */
function preview(venue, rawId, now = new Date()) {
  const couponId = normalizeId(rawId);
  const coupon = couponId ? findCoupon(venue, couponId) : null;
  if (!coupon) return null;
  const verdict = claimVerdict({ coupon, counts: countsOf(venue, couponId), now });
  return { ...publicCoupon(coupon), available: verdict === 'ok' };
}

// ---------- The customer's coupons ----------

/** Everything this person has claimed, open ones first, newest first. */
async function listForUser(userId, { venueId = null, now = new Date(), limit = 100 } = {}) {
  let query = db().collection(CLAIMS).where('userId', '==', String(userId));
  if (venueId) query = query.where('venueId', '==', String(venueId));
  const snap = await query.limit(limit).get();
  const rows = snap.docs.map((d) => claimView({ claimId: d.id, ...d.data() }, now));
  const rank = (c) => (c.status === 'ticket' ? 0 : c.status === 'claimed' ? 1 : c.status === 'used' ? 2 : 3);
  rows.sort((a, b) => rank(a) - rank(b) || String(b.claimedAt || '').localeCompare(String(a.claimedAt || '')));
  return rows;
}

/** The open ones at one store, soonest to end first (the card, the store page, the scan). */
async function openAtVenue(userId, venueId, now = new Date()) {
  const snap = await db().collection(CLAIMS).where('userId', '==', String(userId)).where('venueId', '==', String(venueId)).get();
  return snap.docs.map((d) => ({ claimId: d.id, ...d.data() }))
    .filter((c) => isOpen(c, now))
    .sort((a, b) => String(a.expiresAt).localeCompare(String(b.expiresAt)));
}

// ---------- The ticket at the counter ----------

/**
 * Turns one claimed coupon into a 15-minute ticket: the register scan does
 * this on its own for the coupon ending soonest, "Use now" in the app for a
 * chosen one. A claim that already has a live ticket gets that ticket back.
 */
async function issueTicket({ userId, venueId, claimId: wantedId = null, now = new Date() }) {
  const vouchers = require('./rewardVoucherService');
  const open = await openAtVenue(userId, venueId, now);
  const target = wantedId ? open.find((c) => c.claimId === wantedId) : open[0];
  if (!target) {
    if (wantedId) throw new ServiceError(404, 'coupon_not_open', 'That coupon isn’t open to use.');
    return null;
  }
  if (target.status === 'ticket' && target.voucherId) {
    const doc = await vouchers.voucherRef(target.voucherId).get();
    if (doc.exists && vouchers.effectiveStatus(doc.data(), now.getTime()) === 'issued') {
      return { claim: claimView(target, now), voucher: vouchers.publicVoucher({ voucherId: doc.id, ...doc.data() }, now.getTime()), already: true };
    }
  }

  const rewardService = require('./rewardService');
  const voucherCode = rewardService.generateVoucherCode();
  const expiresAt = new Date(now.getTime() + rewardConfig.VOUCHER_TTL_MINUTES * 60 * 1000).toISOString();
  const eventRef = db().collection(STICKER_COLLECTIONS.REWARD_EVENTS)
    .doc(sanitizeKeyPart(`coupon:${userId}:${venueId}:${target.couponId}:${now.getTime()}`));
  const offer = { offerId: `coupon:${target.couponId}`, title: target.title, pointsCost: 0 };
  const voucher = {
    ...vouchers.newVoucher({ voucherId: eventRef.id, userId: String(userId), venueId, venueName: target.venueName, offer, voucherCode, expiresAt, now }),
    couponClaimId: target.claimId,
    couponId: target.couponId,
    onlineCode: target.onlineCode || null,
    campaign: target.campaign || null
  };
  const event = {
    ...createRewardEvent({
      userId: String(userId), type: EVENT_TYPE, points: 0, venueId, venueName: target.venueName,
      offerId: offer.offerId, offerTitle: target.title, voucherCode, expiresAt, status: 'issued'
    }),
    couponId: target.couponId,
    campaign: target.campaign || null
  };
  event.createdAt = now.toISOString();

  await db().runTransaction(async (tx) => {
    const fresh = await tx.get(claimRef(target.claimId));
    const current = fresh.exists ? fresh.data() : null;
    if (!current || !isOpen(current, now)) throw new ServiceError(409, 'coupon_not_open', 'That coupon isn’t open to use.');
    tx.update(claimRef(target.claimId), { status: 'ticket', voucherId: eventRef.id, ticketAt: now.toISOString() });
    tx.set(eventRef, event);
    tx.set(vouchers.voucherRef(eventRef.id), voucher);
  });
  bump(venueId, target.couponId, 'tickets');
  rewardService.walletBalanceChanged(String(userId), venueId);
  return {
    claim: claimView({ ...target, status: 'ticket', voucherId: eventRef.id }, now),
    voucher: vouchers.publicVoucher(voucher, now.getTime()),
    already: false
  };
}

/** Staff tapped Given on a coupon ticket: the coupon is used, the campaign counts it. */
async function onTicketGiven(voucher, now = new Date()) {
  if (!voucher || !voucher.couponClaimId) return;
  const ref = claimRef(voucher.couponClaimId);
  const doc = await ref.get();
  if (!doc.exists || doc.data().status === 'used') return;
  await ref.update({ status: 'used', usedAt: now.toISOString() });
  await bump(voucher.venueId, voucher.couponId, 'redemptions');
  if (doc.data().newCustomer) await bump(voucher.venueId, voucher.couponId, 'newCustomers');
}

/** A coupon ticket ran out unshown: the coupon goes back to claimed (while its date holds). */
async function onTicketExpired(voucher) {
  if (!voucher || !voucher.couponClaimId) return;
  const ref = claimRef(voucher.couponClaimId);
  const doc = await ref.get();
  if (!doc.exists || doc.data().status !== 'ticket' || doc.data().voucherId !== voucher.voucherId) return;
  await ref.update({ status: 'claimed', voucherId: null, ticketAt: null });
}

// ---------- The campaign's numbers (Insights) ----------

/** Every claim at the store, for the campaigns table. */
async function claimsForVenue(venueId, { limit = 5000 } = {}) {
  const snap = await db().collection(CLAIMS).where('venueId', '==', String(venueId)).limit(limit).get();
  return snap.docs.map((d) => ({ claimId: d.id, ...d.data() }));
}

/**
 * Per coupon: scans, claims, used, new customers, and how many who claimed
 * have bought since (any visit after the claim). Pure.
 */
function campaignRows({ venue, claims = [], visits = [], now = new Date() }) {
  const visitsByUser = new Map();
  visits.forEach((v) => {
    const list = visitsByUser.get(String(v.userId)) || [];
    list.push(String(v.createdAt || ''));
    visitsByUser.set(String(v.userId), list);
  });
  return liveCoupons(venue).map((coupon) => {
    const counts = countsOf(venue, coupon.couponId);
    const mine = claims.filter((c) => c.couponId === coupon.couponId);
    const cameIn = mine.filter((c) => (visitsByUser.get(String(c.userId)) || []).some((at) => at > String(c.claimedAt || ''))).length;
    return {
      couponId: coupon.couponId,
      title: coupon.title,
      campaign: coupon.campaign || null,
      expiresAt: coupon.expiresAt,
      state: ownerCoupon(venue, coupon, now).state,
      scans: counts.scans,
      claims: mine.length || counts.claims,
      used: mine.filter((c) => c.status === 'used').length || counts.redemptions,
      newCustomers: mine.filter((c) => c.newCustomer).length,
      cameIn
    };
  }).sort((a, b) => String(b.expiresAt).localeCompare(String(a.expiresAt)));
}

module.exports = {
  CLAIMS, MAX_COUPONS, MAX_TITLE, MAX_DETAIL, MAX_CAMPAIGN, EVENT_TYPE, ID_RE,
  newCouponId, normalizeId, normalizeCoupon, claimVerdict, ownerCoupon, couponUrl, publicCoupon, claimView, isOpen,
  liveCoupons, findCoupon, countsOf, listForOwner, create, update, remove,
  claim, preview, listForUser, openAtVenue, issueTicket, onTicketGiven, onTicketExpired,
  claimsForVenue, campaignRows
};
