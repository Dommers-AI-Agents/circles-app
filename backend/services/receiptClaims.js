// backend/services/receiptClaims.js
//
// Points for delivery orders (Wes, 2026-11-06): a customer who ordered a
// store's food through DoorDash, Uber Eats or the like never reaches the
// register, so they send the receipt instead. Each store picks (venue field
// `deliveryReceipts`): 'off' (default), 'approve' (the team approves each one)
// or 'auto' (points right away when the receipt checks out; otherwise it
// waits for the team, never refused outright).
//
// The phone reads the receipt (Apple's on-device text recognition — free,
// no model call) and sends the text with the photo. Here: the store name is
// matched against the text, the order date must be within 7 days, and an
// order number earns once per store (receiptOrderNumbers, create()).
// Points are a visit's and count as that day's visit (rewardService
// awardVenueVisit's daily key), so an order and a register scan the same day
// earn once.

const sharp = require('sharp');
const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS, sanitizeKeyPart } = require('../models/StickerModels');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');
const { newId, nowIso } = require('../utils/ids');
const { words } = require('../utils/searchTokens');
const { decode } = require('./scan/images');

const CLAIMS = 'receiptClaims';
const ORDER_NUMBERS = 'receiptOrderNumbers';
const MODES = ['off', 'approve', 'auto'];
const MAX_AGE_DAYS = 7;
const MAX_TEXT = 4000;
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const LONG_EDGE = 1600;
const DAY_MS = 86400000;

// Words too common in store names to identify one ("Sal's Pizza Kitchen" is
// identified by "sal", not "pizza")
const GENERIC = new Set([
  'the', 'and', 'of', 'at', 'on', 'in', 'co', 'company', 'inc', 'llc', 'cafe', 'coffee', 'bar', 'grill', 'kitchen',
  'restaurant', 'pizza', 'pizzeria', 'bakery', 'deli', 'tavern', 'pub', 'house', 'eatery', 'bistro', 'market',
  'shop', 'store', 'food', 'foods', 'express', 'southend', 'uptown', 'downtown', 'charlotte', 'crafted', 'street',
  'greek', 'italian', 'mexican', 'thai', 'chinese', 'japanese', 'indian', 'sushi', 'taco', 'tacos', 'burger', 'burgers',
  'bbq', 'wings', 'bagel', 'bagels', 'donut', 'donuts', 'juice', 'smoothie', 'tea', 'ramen', 'pho', 'noodle', 'noodles'
]);

const db = () => getFirestore();
const mode = (venue) => (MODES.includes(venue && venue.deliveryReceipts) ? venue.deliveryReceipts : 'off');

/** The words that identify a store, from its name(s). Pure. */
function identifyingWords(...names) {
  const all = [...new Set(names.flatMap((n) => words(n || '')))];
  const distinct = all.filter((w) => w.length >= 3 && !GENERIC.has(w));
  return distinct.length ? distinct : all.filter((w) => w.length >= 3);
}

/**
 * Does the receipt's text name this store? Its first identifying word (names
 * lead with what makes them theirs: "Ilios", "Sal's") and half of the rest.
 * Pure.
 */
function matchStoreName(text, ...names) {
  const needed = identifyingWords(...names);
  if (!needed.length) return false;
  const have = new Set(words(text || ''));
  const found = needed.filter((w) => have.has(w)).length;
  return have.has(needed[0]) && found >= Math.ceil(needed.length / 2);
}

/** 'ok' | 'missing' | 'too_old' | 'future' for the order date the phone read. Pure. */
function dateCheck(orderDate, now = new Date()) {
  const t = Date.parse(orderDate || '');
  if (!Number.isFinite(t)) return 'missing';
  if (t > now.getTime() + DAY_MS) return 'future';
  if (t < now.getTime() - MAX_AGE_DAYS * DAY_MS - DAY_MS / 2) return 'too_old';
  return 'ok';
}

/** "#A1B2-c3" → "A1B2C3"; null when too short to identify an order. Pure. */
function normalizeOrderNumber(raw) {
  const n = String(raw || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  return n.length >= 4 && n.length <= 40 ? n : null;
}

const orderNumberRef = (venueId, number) => db().collection(ORDER_NUMBERS).doc(`${venueId}__${number}`);
// rewardService.awardVenueVisit's daily key, as the event doc id
const visitKey = (userId, venueId, day) => sanitizeKeyPart(`visit:${userId}:${venueId}:${day}`);

async function loadVenue(venueId) {
  const doc = await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId)).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'Store not found');
  return { venueId: doc.id, ...doc.data() };
}

const teamOf = (venue) => [...new Set([venue.ownerUserId, ...require('./venueHelpers').venueManagerIds(venue)]
  .filter(Boolean).map(String))];

function push(userId, type, title, body, data) {
  require('./notifyQuiet').sendInBackground(userId, { type, title, body, data }, type);
}

async function storeImage(path, input) {
  const buf = decode(input);
  if (!buf) throw new ServiceError(400, 'bad_image', 'Add a photo or screenshot of the receipt.');
  if (buf.length > MAX_IMAGE_BYTES) throw new ServiceError(413, 'image_too_large', 'That photo is too large.');
  let jpeg;
  try {
    jpeg = await sharp(buf).rotate()
      .resize({ width: LONG_EDGE, height: LONG_EDGE, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 80 }).toBuffer();
  } catch (e) {
    throw new ServiceError(400, 'bad_image', 'That photo couldn’t be read.');
  }
  // Private: receipts carry a delivery address. The team sees it through a
  // short-lived signed link (listForVenue).
  const bucket = require('firebase-admin/storage').getStorage().bucket();
  await bucket.file(path).save(jpeg, { contentType: 'image/jpeg', resumable: false });
}

/**
 * The customer sends a receipt. Returns { status: 'approved'|'pending', points?,
 * venueBalance? }. Refuses (ServiceError) when the store doesn't take
 * receipts, rewards are paused, the customer was removed, they already earned
 * here today, the order is over a week old, or the order number was used.
 */
async function submit(userId, venueId, body = {}, { now = new Date() } = {}) {
  const rewardService = require('./rewardService');
  const venue = await loadVenue(venueId);
  const storeMode = mode(venue);
  if (storeMode === 'off') throw new ServiceError(403, 'receipts_off', `${venue.venueName} doesn’t give points for delivery orders.`);
  const { earns } = await require('./ownerSubscriptionService').registerScanEarns(venue);
  if (!earns) throw new ServiceError(409, 'rewards_paused', `${venue.venueName}’s rewards are paused right now.`);
  if (await require('./storeCustomers').isRemoved(userId, venue.venueId)) {
    throw new ServiceError(403, 'removed', `${venue.venueName} took you off its rewards.`);
  }

  const receipt = body.receipt || {};
  const text = String(receipt.text || '').slice(0, MAX_TEXT);
  const date = dateCheck(receipt.orderDate, now);
  if (date === 'too_old') throw new ServiceError(400, 'too_old', `Receipts earn points for ${MAX_AGE_DAYS} days after the order.`);
  const day = now.toISOString().slice(0, 10);
  const earnedToday = await db().collection(STICKER_COLLECTIONS.REWARD_EVENTS).doc(visitKey(userId, venue.venueId, day)).get();
  if (earnedToday.exists) throw new ServiceError(409, 'already_today', `You already earned at ${venue.venueName} today. Send it tomorrow.`);

  const budget = await require('./dailyBudget').consume('receiptClaim', userId);
  if (!budget.allowed) throw new ServiceError(429, 'too_many', 'That’s enough receipts for today.');

  const orderNumber = normalizeOrderNumber(receipt.orderNumber);
  const checks = {
    storeName: matchStoreName(text, venue.venueName, venue.placeName),
    date: date === 'ok',
    orderNumber: !!orderNumber
  };
  const claimId = newId();
  // The order number earns once per store, whoever sends it
  if (orderNumber) {
    try {
      await orderNumberRef(venue.venueId, orderNumber).create({ venueId: venue.venueId, claimId, userId: String(userId), createdAt: nowIso() });
    } catch (error) {
      if (error.code === 6 || /already exists/i.test(error.message || '')) {
        throw new ServiceError(409, 'order_used', 'That order already earned points.');
      }
      throw error;
    }
  }
  const imagePath = `receipts/${venue.venueId}/${claimId}.jpg`;
  try {
    await storeImage(imagePath, body.image);
  } catch (error) {
    if (orderNumber) await orderNumberRef(venue.venueId, orderNumber).delete().catch(() => {});
    throw error;
  }

  const claim = {
    venueId: venue.venueId,
    venueName: venue.venueName || null,
    // The customer's answer opens the store's place page
    globalPlaceId: venue.globalPlaceId || null,
    userId: String(userId),
    status: 'pending',
    mode: storeMode,
    checks,
    receipt: {
      storeLine: String(receipt.storeLine || '').slice(0, 120) || null,
      orderDate: receipt.orderDate ? String(receipt.orderDate).slice(0, 40) : null,
      orderNumber,
      deliveryApp: String(receipt.deliveryApp || '').slice(0, 40) || null,
      total: String(receipt.total || '').slice(0, 20) || null,
      text
    },
    imagePath,
    day,
    createdAt: now.toISOString()
  };
  const ref = db().collection(CLAIMS).doc(claimId);
  await ref.set(claim);

  if (storeMode === 'auto' && checks.storeName && checks.date && checks.orderNumber) {
    const result = await award(venue, ref, claim, 'auto');
    if (result.awarded) {
      const { venueBalances } = await rewardService.getBalance(userId, { withEvents: false });
      const venueBalance = (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0;
      return { claimId, status: 'approved', points: result.points, venueBalance };
    }
  }
  teamOf(venue).forEach((memberId) => push(memberId, 'receipt_new', 'A delivery receipt to approve',
    `Someone sent a ${claim.receipt.deliveryApp || 'delivery'} receipt for ${venue.venueName}`,
    { venueId: venue.venueId, claimId }));
  return { claimId, status: 'pending' };
}

/** Pays the claim (the visit's daily key, keyed to the day it was sent). */
async function award(venue, ref, claim, decidedBy) {
  const result = await require('./rewardService').awardVenueVisit(claim.userId, venue, {
    via: 'delivery_receipt', day: claim.day
  });
  await ref.update({
    status: 'approved',
    decidedBy: String(decidedBy),
    decidedAt: nowIso(),
    points: result.awarded ? result.points : 0,
    ...(result.awarded ? {} : { outcome: result.reason || 'not_awarded' })
  });
  return result;
}

/** Moves a pending claim to `status` exactly once (a second tap gets 409). */
async function takePending(venueId, claimId) {
  const ref = db().collection(CLAIMS).doc(String(claimId));
  const claim = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data().venueId !== venueId) throw new ServiceError(404, 'not_found', 'Receipt not found');
    if (snap.data().status !== 'pending') throw new ServiceError(409, 'already_decided', 'This receipt was already answered.');
    tx.update(ref, { status: 'deciding' });
    return snap.data();
  });
  return { ref, claim };
}

/** The team gives the points. */
async function approve(venue, claimId, actorId) {
  const { ref, claim } = await takePending(venue.venueId, claimId);
  let result;
  try {
    result = await award(venue, ref, claim, actorId);
  } catch (error) {
    await ref.update({ status: 'pending' }).catch(() => {});
    throw error;
  }
  if (result.awarded) {
    push(claim.userId, 'receipt_result', `${venue.venueName} gave you ${result.points} points`,
      'For your delivery order. Thanks for ordering!', { venueId: venue.venueId, placeId: claim.globalPlaceId || null, claimId: ref.id, approved: true });
  } else if (result.reason === 'already_today') {
    push(claim.userId, 'receipt_result', `${venue.venueName} approved your receipt`,
      'You’d already earned there that day, so no extra points this time.', { venueId: venue.venueId, placeId: claim.globalPlaceId || null, claimId: ref.id, approved: true });
  }
  return { approved: true, points: result.awarded ? result.points : 0, alreadyEarned: result.reason === 'already_today' };
}

/** The team says no; the customer is told. The order number stays used. */
async function decline(venue, claimId, actorId) {
  const { ref, claim } = await takePending(venue.venueId, claimId);
  await ref.update({ status: 'declined', decidedBy: String(actorId), decidedAt: nowIso() });
  await require('./scanAttempts').recordScanAttempt(claim.userId, venue, { reason: 'receipt_declined' }).catch(() => {});
  push(claim.userId, 'receipt_result', `${venue.venueName} couldn’t match your receipt`,
    'No points this time. Questions? Ask the store.', { venueId: venue.venueId, placeId: claim.globalPlaceId || null, claimId: ref.id, approved: false });
  return { declined: true };
}

/** The team's queue, newest first, with who sent each and a 1-hour photo link. */
async function listForVenue(venue, { status = 'pending', limit = 100 } = {}) {
  const snap = await db().collection(CLAIMS)
    .where('venueId', '==', venue.venueId)
    .where('status', '==', status)
    .orderBy('createdAt', 'desc').limit(limit).get();
  const rows = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  const ids = [...new Set(rows.map((r) => r.userId))];
  const users = ids.length ? await db().getAll(...ids.map((id) => db().collection(COLLECTIONS.USERS).doc(id))) : [];
  const cards = new Map(users.filter((d) => d.exists).map((d) => [d.id, {
    id: d.id, displayName: d.data().displayName || 'FavCircles user', profilePicture: d.data().profilePicture || null
  }]));
  const bucket = require('firebase-admin/storage').getStorage().bucket();
  const expires = Date.now() + 60 * 60 * 1000;
  return Promise.all(rows.map(async (r) => ({
    claimId: r.id,
    status: r.status,
    createdAt: r.createdAt,
    checks: r.checks,
    receipt: { ...r.receipt, text: undefined },
    user: cards.get(r.userId) || null,
    imageUrl: await bucket.file(r.imagePath).getSignedUrl({ version: 'v4', action: 'read', expires })
      .then(([url]) => url).catch(() => null)
  })));
}

/** How many wait for the team (Manage Store's badge). */
async function pendingCount(venue) {
  if (mode(venue) === 'off') return 0;
  try {
    const snap = await db().collection(CLAIMS)
      .where('venueId', '==', venue.venueId)
      .where('status', '==', 'pending').count().get();
    return snap.data().count;
  } catch (e) {
    console.warn('Pending receipt count failed:', e.message);
    return 0;
  }
}

/** Receipts nobody answered in 7 days lapse; the customer is told. */
async function expireOld({ now = new Date() } = {}) {
  const cutoff = new Date(now.getTime() - MAX_AGE_DAYS * DAY_MS).toISOString();
  const snap = await db().collection(CLAIMS).where('status', '==', 'pending').where('createdAt', '<', cutoff).limit(200).get();
  for (const doc of snap.docs) {
    const claim = doc.data();
    await doc.ref.update({ status: 'expired', decidedAt: now.toISOString() });
    push(claim.userId, 'receipt_result', `${claim.venueName || 'The store'} didn’t get to your receipt`,
      'It wasn’t answered within a week, so it expired.', { venueId: claim.venueId, placeId: claim.globalPlaceId || null, claimId: doc.id, approved: false });
  }
  return { expired: snap.size };
}

/** The store's setting. */
async function setMode(venue, value) {
  if (!MODES.includes(value)) throw new ServiceError(400, 'invalid_mode', 'Pick off, approve or auto.');
  await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId).update({ deliveryReceipts: value });
  return { deliveryReceipts: value };
}

module.exports = {
  MODES, MAX_AGE_DAYS, mode,
  identifyingWords, matchStoreName, dateCheck, normalizeOrderNumber,
  submit, approve, decline, listForVenue, pendingCount, expireOld, setMode
};
