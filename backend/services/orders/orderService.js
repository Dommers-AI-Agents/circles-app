// backend/services/orders/orderService.js — order ahead from a store's full
// menu, pay at pickup (Wes, 2026-10-20). Business stores that switched
// ordering on; pickup only. No money moves through FavCircles: the order
// carries an estimate and the store charges at the counter.
//
// One `orders/{orderId}` doc per order, read by the customer and the
// store's team. Every step pushes the other side; a new order also emails
// the team. Orders nobody answers expire after 30 minutes (sweep).
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const { isSameUser } = require('../idService');
const { isVenueTeamMember, venueManagerIds } = require('../venueHelpers');
const { isVenueBusinessLive } = require('../ownerSubscriptionService');
const dailyBudget = require('../dailyBudget');
const { sendInBackground } = require('../notifyQuiet');
const { escapeHtml } = require('../../utils/text');
const rules = require('./orderRules');

const ORDERS = 'orders';
const { STATUS, OPEN, LIMITS } = rules;

const nowIso = () => new Date().toISOString();
const team = (venue) => [venue.ownerUserId, ...venueManagerIds(venue)].filter(Boolean);

async function loadVenue(db, venueId) {
  const doc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId || '')).get();
  if (!doc.exists) throw new ServiceError(404, 'store_not_found', 'That store isn’t taking orders.');
  return { venueId: doc.id, ...doc.data() };
}

/** What the customer and the store both see. */
const view = (id, o) => ({
  orderId: id,
  test: o.test === true,
  venueId: o.venueId,
  venueName: o.venueName,
  globalPlaceId: o.globalPlaceId || null,
  customerId: o.customerId,
  customerName: o.customerName,
  lines: o.lines,
  note: o.note || null,
  pickup: o.pickup,
  estimate: o.estimate,
  estimateIsPartial: !!o.estimateIsPartial,
  status: o.status,
  statusLabel: rules.label(o.status),
  readyAt: o.readyAt || null,
  declineReason: o.declineReason || null,
  createdAt: o.createdAt,
  updatedAt: o.updatedAt
});

const summary = (lines) => lines.map((l) => `${l.qty}× ${l.name}`).join(', ');
const timeText = (iso, timeZone) => {
  try {
    return new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', timeZone: timeZone || 'America/New_York' }).format(new Date(iso));
  } catch (e) { return ''; }
};

// ---------------------------------------------------------------- customer

/**
 * `test`: the store's own team trying it as a customer ("Try it as a
 * customer"): allowed before ordering is switched on, marked TEST, no
 * email and no daily allowance spent. App Review uses it (2026-10-21).
 * Only stores whose owner pays for Business take orders: no comps.
 */
async function place({ customerId, venueId, items, note, pickup, test = false }, { db = getFirestore(), now = new Date() } = {}) {
  const venue = await loadVenue(db, venueId);
  const live = await isVenueBusinessLive(venue);
  const onTeam = isVenueTeamMember(venue, customerId);
  if (test && !onTeam) throw new ServiceError(403, 'not_your_store', 'Test orders are for the store’s own team.');
  if (test && !live) throw new ServiceError(403, 'business_required', 'Online ordering is part of FavCircles Business.');
  const ordering = test
    ? rules.orderingFor({ ...venue, ordering: { ...(venue.ordering || {}), enabled: true } }, { live })
    : rules.orderingFor(venue, { live });
  if (!ordering) {
    throw new ServiceError(409, test ? 'no_menu' : 'ordering_off',
      test ? 'Add your full menu first; customers order from it.' : 'This store isn’t taking orders in the app right now.');
  }
  if (!test && onTeam) throw new ServiceError(400, 'own_store', 'To try your own store, use “Try it as a customer” in Online ordering.');

  const priced = rules.priceCart(venue.storefront.menu, items);
  const when = rules.pickupFor(pickup, { leadMinutes: ordering.leadMinutes, now });

  const open = await db.collection(ORDERS).where('customerId', '==', customerId).where('status', 'in', [...OPEN]).get();
  if (open.size >= LIMITS.openPerCustomer) {
    throw new ServiceError(429, 'too_many_open', 'You have a few orders in progress. Pick those up first.');
  }
  if (!test) {
    const budget = await dailyBudget.consume('orderPlace', customerId);
    if (!budget.allowed) throw new ServiceError(429, 'order_limit', 'That’s a lot of orders for one day. Try again tomorrow.');
  }

  const userDoc = await db.collection('users').doc(customerId).get();
  const customerName = (userDoc.exists && (userDoc.data().displayName || '').trim()) || 'A customer';
  const ref = db.collection(ORDERS).doc();
  const order = {
    venueId: venue.venueId,
    venueName: venue.name || venue.placeName || 'the store',
    globalPlaceId: venue.globalPlaceId || null,
    timeZone: venue.timeZone || null,
    team: team(venue),
    customerId,
    customerName,
    lines: priced.lines,
    note: String(note || '').trim().slice(0, LIMITS.orderNote) || null,
    pickup: when,
    estimate: priced.estimate,
    estimateIsPartial: priced.estimateIsPartial,
    status: STATUS.PLACED,
    test: test === true,
    history: [{ status: STATUS.PLACED, at: now.toISOString(), by: customerId }],
    createdAt: now.toISOString(),
    updatedAt: now.toISOString()
  };
  await ref.set(order);
  notifyTeamOfNewOrder(db, ref.id, order).catch((e) => console.error('order: team notice failed', e.message));
  return view(ref.id, order);
}

async function mine(customerId, { db = getFirestore() } = {}) {
  const snap = await db.collection(ORDERS).where('customerId', '==', customerId).orderBy('createdAt', 'desc').limit(30).get();
  return snap.docs.map((d) => view(d.id, d.data()));
}

/**
 * The customer's open orders at one store, newest first, for the store's
 * place page: a banner per order so the status is one tap away after the
 * first screen is gone, and two orders never hide each other (Wes,
 * 2026-10-28). Open orders are capped at 3 per customer, so the status
 * filter keeps this to a handful of docs.
 */
async function openOrdersAtVenue(customerId, venueId, { db = getFirestore() } = {}) {
  const snap = await db.collection(ORDERS)
    .where('customerId', '==', customerId)
    .where('status', 'in', [...OPEN])
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((o) => o.venueId === venueId)
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .map((o) => view(o.id, o));
}

/** One order, for its customer or the store's team. */
async function get(orderId, viewerId, { db = getFirestore() } = {}) {
  const doc = await db.collection(ORDERS).doc(String(orderId || '')).get();
  if (!doc.exists) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
  const o = doc.data();
  const allowed = isSameUser(o.customerId, viewerId) || (o.team || []).some((id) => isSameUser(id, viewerId));
  if (!allowed) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
  return view(doc.id, o);
}

async function cancel(orderId, customerId, { db = getFirestore() } = {}) {
  return act(orderId, 'cancel', { by: 'customer', actorId: customerId, db });
}

/** The customer has the order in hand: it leaves their page and the store's board. */
async function pickedUp(orderId, customerId, { db = getFirestore() } = {}) {
  return act(orderId, 'picked_up', { by: 'customer', actorId: customerId, db });
}

// ------------------------------------------------------------------- store

/**
 * Orders waiting for the store to accept them: the owner bar on the place
 * page and the profile's store icon show it (2026-10-23). 0 when ordering is
 * off or the count can't be read: it's a nudge, never a blocker.
 */
async function newCount(venue, { db = getFirestore() } = {}) {
  if (!venue || !venue.ordering || venue.ordering.enabled !== true) return 0;
  try {
    const snap = await db.collection(ORDERS)
      .where('venueId', '==', venue.venueId || venue.id)
      .where('status', '==', STATUS.PLACED).get();
    return snap.size;
  } catch (e) {
    console.warn('New-order count failed:', e.message);
    return 0;
  }
}

async function forVenue(venueId, { db = getFirestore(), open = true } = {}) {
  let q = db.collection(ORDERS).where('venueId', '==', venueId);
  q = open ? q.where('status', 'in', [...OPEN]) : q.orderBy('createdAt', 'desc').limit(50);
  const snap = await q.get();
  const list = snap.docs.map((d) => view(d.id, d.data()));
  // Oldest waiting first: the counter works through them in order
  return open ? list.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt))) : list;
}

/**
 * The store moves an order on: accept (with minutes until ready), ready,
 * picked_up, decline (with an optional reason). `venueId` must be the
 * order's store (the route already checked the caller is on its team).
 */
async function storeAction(venueId, orderId, action, { actorId, readyInMinutes, reason, db = getFirestore() } = {}) {
  return act(orderId, action, { by: 'store', venueId, actorId, readyInMinutes, reason, db });
}

async function act(orderId, action, { by, venueId, actorId, readyInMinutes, reason, db, now = new Date() }) {
  const ref = db.collection(ORDERS).doc(String(orderId || ''));
  const result = await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
    const o = doc.data();
    if (by === 'customer' && !isSameUser(o.customerId, actorId)) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
    if (by === 'store' && o.venueId !== venueId) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
    const to = rules.transition(o, action, by);
    const patch = { status: to, updatedAt: now.toISOString(), history: [...(o.history || []), { status: to, at: now.toISOString(), by: actorId }] };
    if (action === 'accept') {
      const minutes = Math.min(LIMITS.maxReadyMinutes, Math.max(0, Math.round(Number(readyInMinutes) || 0)));
      const base = o.pickup && !o.pickup.asap && o.pickup.at ? new Date(o.pickup.at) : now;
      patch.readyAt = new Date(Math.max(base.getTime(), now.getTime() + minutes * 60000)).toISOString();
    }
    if (action === 'decline') patch.declineReason = String(reason || '').trim().slice(0, 200) || null;
    tx.update(ref, patch);
    return { id: doc.id, order: { ...o, ...patch } };
  });
  notifyStep(result.id, result.order, action, by);
  return view(result.id, result.order);
}

// --------------------------------------------------------------- settings

/** Owner turns ordering on/off and sets the usual prep time (Business). */
function normalizeSettings(input = {}) {
  const lead = Math.round(Number(input.leadMinutes));
  return {
    enabled: input.enabled === true,
    leadMinutes: Number.isFinite(lead) ? Math.min(120, Math.max(5, lead)) : rules.DEFAULT_LEAD_MINUTES,
    note: String(input.note || '').trim().slice(0, 200) || null,
    updatedAt: nowIso()
  };
}

async function saveSettings(venue, input, { db = getFirestore() } = {}) {
  const value = normalizeSettings(input);
  const sections = (venue.storefront && venue.storefront.menu && venue.storefront.menu.sections) || [];
  if (value.enabled && !sections.some((s) => (s.items || []).length)) {
    throw new ServiceError(400, 'no_menu', 'Add your full menu first; customers order from it.');
  }
  await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId).update({ ordering: value, updatedAt: nowIso() });
  return value;
}

// ---------------------------------------------------------------- notices

async function notifyTeamOfNewOrder(db, orderId, o) {
  const when = o.pickup.asap ? 'as soon as possible' : `at ${timeText(o.pickup.at, o.timeZone)}`;
  const title = `${o.test ? 'Test order' : 'New order'}: ${o.customerName}`;
  const body = `${summary(o.lines)}. Pickup ${when}. Tap to accept.`;
  for (const uid of o.team) {
    sendInBackground(uid, { type: 'order_new', title, body, data: { orderId, venueId: o.venueId } }, 'order_new');
  }
  // Email too: a counter may not have the app open (Wes: push + email).
  // Not for a test order the owner just placed themselves.
  if (o.test) return;
  const emailService = require('../emailService');
  const docs = await Promise.all(o.team.map((uid) => db.collection('users').doc(uid).get()));
  const rows = o.lines.map((l) => `<tr><td style="padding:4px 12px 4px 0">${l.qty}×</td><td style="padding:4px 12px 4px 0"><b>${escapeHtml(l.name)}</b>${l.note ? `<br><i>${escapeHtml(l.note)}</i>` : ''}</td><td style="padding:4px 0;text-align:right">${escapeHtml(l.price || '')}</td></tr>`).join('');
  const estimate = o.estimate ? `About $${o.estimate.toFixed(2)}${o.estimateIsPartial ? ' (plus items priced at the counter)' : ''}, paid at pickup.` : 'Paid at pickup.';
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px">
<h2 style="margin:0 0 6px">New order from ${escapeHtml(o.customerName)}</h2>
<p style="margin:0 0 14px;color:#555">${escapeHtml(o.venueName)} · pickup ${escapeHtml(when)}</p>
<table style="border-collapse:collapse;font-size:15px">${rows}</table>
${o.note ? `<p style="margin:14px 0 0"><b>Note:</b> ${escapeHtml(o.note)}</p>` : ''}
<p style="margin:14px 0">${escapeHtml(estimate)}</p>
<p style="margin:18px 0"><b>Open FavCircles to accept it</b> (your store → Orders). If nobody answers in 30 minutes, the customer is told the order wasn’t taken.</p>
</div>`;
  const text = `New order from ${o.customerName} (${o.venueName}), pickup ${when}\n${o.lines.map((l) => `${l.qty}x ${l.name}${l.note ? ` (${l.note})` : ''} ${l.price || ''}`).join('\n')}${o.note ? `\nNote: ${o.note}` : ''}\n${estimate}\nOpen FavCircles to accept it (your store -> Orders).`;
  for (const d of docs) {
    const email = d.exists && d.data().email;
    if (!email) continue;
    await emailService.sendEmail({ to: email, subject: `New FavCircles order: ${summary(o.lines).slice(0, 80)}`, html, text })
      .catch((e) => console.error('order email failed', e.message));
  }
}

function notifyStep(orderId, o, action, by = 'store') {
  const place = o.venueName;
  const notice = {
    accept: { title: `${place} accepted your order`, body: `Ready around ${timeText(o.readyAt, o.timeZone)}. Pay at pickup.` },
    ready: { title: `Your order is ready at ${place}`, body: 'Head to the counter to pick it up and pay.' },
    decline: { title: `${place} couldn’t take your order`, body: o.declineReason || 'They can’t make it right now.' },
    // The counter marking it needs no notice; the customer marking it tells
    // the counter the order is off their board
    picked_up: by === 'customer' ? { team: true, title: `Picked up: ${o.customerName}`, body: `${summary(o.lines)}. The customer has it.` } : null,
    cancel: { team: true, title: `Order cancelled: ${o.customerName}`, body: `${summary(o.lines)}. No need to make it.` },
    expire: { title: `${place} didn’t answer your order`, body: 'It wasn’t taken, so don’t head over for it. Try calling the store.' }
  }[action];
  if (!notice) return;
  const data = { orderId, venueId: o.venueId, status: o.status };
  if (notice.team) {
    for (const uid of o.team || []) sendInBackground(uid, { type: 'order_new', title: notice.title, body: notice.body, data }, 'order_cancel');
  } else {
    sendInBackground(o.customerId, { type: 'order_update', title: notice.title, body: notice.body, data }, 'order_update');
  }
}

// ------------------------------------------------------------------ sweep

/** Placed orders nobody answered in 30 min expire (customer told); ready
 * orders nobody closed in 12 h are closed quietly. */
async function sweep({ db = getFirestore(), now = new Date() } = {}) {
  let expired = 0; let closed = 0;
  const answerBy = new Date(now.getTime() - LIMITS.answerMinutes * 60000).toISOString();
  const stale = await db.collection(ORDERS).where('status', '==', STATUS.PLACED).where('createdAt', '<=', answerBy).limit(200).get();
  for (const doc of stale.docs) {
    const o = doc.data();
    const patch = { status: STATUS.EXPIRED, updatedAt: now.toISOString(), history: [...(o.history || []), { status: STATUS.EXPIRED, at: now.toISOString(), by: 'system' }] };
    await doc.ref.update(patch);
    notifyStep(doc.id, { ...o, ...patch }, 'expire');
    expired += 1;
  }
  const closeBy = new Date(now.getTime() - LIMITS.closeReadyAfterHours * 3600000).toISOString();
  const ready = await db.collection(ORDERS).where('status', '==', STATUS.READY).where('updatedAt', '<=', closeBy).limit(200).get();
  for (const doc of ready.docs) {
    const o = doc.data();
    await doc.ref.update({ status: STATUS.PICKED_UP, updatedAt: now.toISOString(), history: [...(o.history || []), { status: STATUS.PICKED_UP, at: now.toISOString(), by: 'system' }] });
    closed += 1;
  }
  return { expired, closed };
}

module.exports = { ORDERS, view, place, mine, openOrdersAtVenue, get, cancel, pickedUp, newCount, forVenue, storeAction, normalizeSettings, saveSettings, sweep };
