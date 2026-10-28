// backend/services/orders/orderRules.js — order ahead, pay at pickup (Wes,
// 2026-10-20). Pure rules: what a customer can order from a store's full
// menu, the estimate shown (payment happens at the counter), and which
// status can follow which. orderService does the I/O.
const { ServiceError } = require('../../utils/serviceError');

const STATUS = {
  PLACED: 'placed',        // sent, waiting for the store
  ACCEPTED: 'accepted',    // the store took it and gave a ready time
  READY: 'ready',          // ready at the counter
  PICKED_UP: 'picked_up',  // done
  DECLINED: 'declined',    // the store said no (or cancelled after accepting)
  CANCELLED: 'cancelled',  // the customer withdrew it before it was accepted
  EXPIRED: 'expired'       // nobody at the store answered in time
};
const OPEN = new Set([STATUS.PLACED, STATUS.ACCEPTED, STATUS.READY]);

const LIMITS = {
  lines: 50, qty: 20, lineNote: 200, orderNote: 300,
  openPerCustomer: 3,
  answerMinutes: 30,          // a placed order nobody answers expires
  closeReadyAfterHours: 12,   // a ready order nobody marked picked up closes
  maxReadyMinutes: 240,
  laterMaxHours: 24
};
const DEFAULT_LEAD_MINUTES = 15;

/** Who may move an order from one status to the next. */
const TRANSITIONS = {
  accept: { by: 'store', from: [STATUS.PLACED], to: STATUS.ACCEPTED },
  ready: { by: 'store', from: [STATUS.PLACED, STATUS.ACCEPTED], to: STATUS.READY },
  // The customer can say they have it too (Wes, 2026-10-28): the ready
  // notice shouldn't wait on the counter remembering to tap
  picked_up: { by: ['store', 'customer'], from: [STATUS.ACCEPTED, STATUS.READY], to: STATUS.PICKED_UP },
  decline: { by: 'store', from: [STATUS.PLACED, STATUS.ACCEPTED], to: STATUS.DECLINED },
  cancel: { by: 'customer', from: [STATUS.PLACED], to: STATUS.CANCELLED }
};

function transition(order, action, by) {
  const t = TRANSITIONS[action];
  if (!t || ![].concat(t.by).includes(by)) throw new ServiceError(400, 'bad_action', 'That can’t be done to an order.');
  if (!t.from.includes(order.status)) {
    throw new ServiceError(409, 'order_moved_on', `This order is already ${label(order.status).toLowerCase()}.`);
  }
  return t.to;
}

const label = (status) => ({
  placed: 'Waiting for the store', accepted: 'Accepted', ready: 'Ready for pickup', picked_up: 'Picked up',
  declined: 'Declined', cancelled: 'Cancelled', expired: 'Not answered'
}[status] || status);

/** "16" / "$16.50" / "16.50 USD" → 16.5; "MP", "8 / 14", "glass 10 · bottle 36" → null. Pure. */
function priceValue(price) {
  const m = String(price || '').trim().match(/^\$?\s*(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:usd|dollars?)?$/i);
  return m ? Number(m[1].replace(',', '.')) : null;
}

/** Ordering as a customer sees it: on, with a menu, while the store's Business is live. Pure. */
function orderingFor(venue, { live }) {
  const o = (venue && venue.ordering) || {};
  const sections = (venue && venue.storefront && venue.storefront.menu && venue.storefront.menu.sections) || [];
  const hasItems = sections.some((s) => (s.items || []).length);
  if (!live || o.enabled !== true || !hasItems) return null;
  return {
    enabled: true,
    leadMinutes: Number.isFinite(o.leadMinutes) ? o.leadMinutes : DEFAULT_LEAD_MINUTES,
    note: o.note || null
  };
}

/**
 * The customer's cart checked against the store's menu: every line must be
 * an item on the menu (names and prices come from the menu, never the
 * phone), quantities 1–20. Returns { lines, estimate, estimateIsPartial }.
 */
function priceCart(menu, cart) {
  const items = new Map();
  for (const s of (menu && menu.sections) || []) for (const it of s.items || []) items.set(it.id, { ...it, section: s.name });
  const lines = [];
  for (const raw of Array.isArray(cart) ? cart : []) {
    const item = items.get(String(raw && raw.itemId));
    if (!item) throw new ServiceError(409, 'menu_changed', 'The menu changed since you opened it. Check your order and try again.');
    const qty = Math.floor(Number(raw.qty));
    if (!Number.isFinite(qty) || qty < 1 || qty > LIMITS.qty) throw new ServiceError(400, 'bad_quantity', `Quantities are 1 to ${LIMITS.qty}.`);
    const note = String(raw.note || '').trim().slice(0, LIMITS.lineNote) || null;
    lines.push({ itemId: item.id, name: item.name, section: item.section, price: item.price || null, qty, note });
  }
  if (!lines.length) throw new ServiceError(400, 'empty_order', 'Add something from the menu first.');
  if (lines.length > LIMITS.lines) throw new ServiceError(400, 'too_many_lines', `Up to ${LIMITS.lines} different items in one order.`);
  let estimate = 0; let partial = false;
  for (const l of lines) {
    const v = priceValue(l.price);
    if (v === null) partial = true; else estimate += v * l.qty;
  }
  return { lines, estimate: Math.round(estimate * 100) / 100, estimateIsPartial: partial };
}

/** 'asap' or an ISO time at least the lead time out and within 24 h. Pure. */
function pickupFor(requested, { leadMinutes = DEFAULT_LEAD_MINUTES, now = new Date() } = {}) {
  if (!requested || requested === 'asap') return { asap: true, at: null };
  const at = new Date(requested);
  if (Number.isNaN(at.getTime())) throw new ServiceError(400, 'bad_pickup', 'Choose a pickup time.');
  const earliest = now.getTime() + (leadMinutes - 2) * 60000;
  if (at.getTime() < earliest) throw new ServiceError(400, 'pickup_too_soon', `The store needs about ${leadMinutes} minutes. Choose a later time or "As soon as possible".`);
  if (at.getTime() > now.getTime() + LIMITS.laterMaxHours * 3600000) throw new ServiceError(400, 'pickup_too_late', 'Orders can be placed up to 24 hours ahead.');
  return { asap: false, at: at.toISOString() };
}

module.exports = { STATUS, OPEN, LIMITS, DEFAULT_LEAD_MINUTES, TRANSITIONS, transition, label, priceValue, orderingFor, priceCart, pickupFor };
