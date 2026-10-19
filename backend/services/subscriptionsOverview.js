// Every subscription a person pays FavCircles for, in one list (Wes,
// 2026-10-19: a $7.99 charge he couldn't place — Fridge Mail, billed by card
// — and a cancel button that was hard to find). Settings → Subscriptions
// shows this list; the app adds the App Store's own price and renewal state
// for the Apple ones.
const { getFirestore } = require('../config/firebase');
const { SUBSCRIPTION_PRICE_CENTS, SUB_ACTIVE } = require('./fridgeMail/shared');

const APPLE_LIVE = new Set(['active', 'trial', 'grace_period']);

const isFuture = (iso, now) => !!iso && Date.parse(iso) > now;

function appleEntry({ id, name, what, productId, status, expiry, now }) {
  if (!productId || !APPLE_LIVE.has(status) || (expiry && !isFuture(expiry, now))) return null;
  return {
    id, name, what, billedBy: 'apple', productId,
    period: /annual|yearly/i.test(productId) ? 'year' : 'month',
    priceCents: null,                 // the App Store's price, filled in on the phone
    status: status === 'grace_period' ? 'payment_issue' : 'active',
    periodEnd: expiry || null,
    willRenew: null,                  // only the App Store knows; the phone asks it
    manage: 'appstore'
  };
}

function fridgeEntry(plan, now) {
  const sub = plan && plan.subscription;
  if (!sub || !(SUB_ACTIVE.has(sub.status) || sub.status === 'past_due')) return null;
  if (sub.currentPeriodEnd && !isFuture(sub.currentPeriodEnd, now) && sub.cancelAtPeriodEnd) return null;
  const quantity = Math.max(1, sub.quantity || 1);
  const names = (plan.recipients || []).map((r) => r.name).filter(Boolean);
  return {
    id: 'fridgemail', name: 'Fridge Mail',
    what: quantity === 1
      ? `A printed card of your kid's drawing every week${names[0] ? ` to ${names[0]}` : ''}`
      : `A printed card every week to each of ${quantity} grandparents`,
    billedBy: 'card', productId: null, period: 'month',
    priceCents: SUBSCRIPTION_PRICE_CENTS * quantity,
    unitPriceCents: SUBSCRIPTION_PRICE_CENTS, quantity,
    status: sub.status === 'past_due' ? 'payment_issue' : 'active',
    periodEnd: sub.currentPeriodEnd || null,
    willRenew: !sub.cancelAtPeriodEnd,
    manage: 'fridgemail'
  };
}

async function listSubscriptions(userId, { now = Date.now(), db = getFirestore() } = {}) {
  const [userDoc, planDoc] = await Promise.all([
    db.collection('users').doc(userId).get(),
    db.collection('fridgeMailPlans').doc(userId).get()
  ]);
  const u = userDoc.exists ? userDoc.data() : {};
  return [
    appleEntry({ id: 'premium', name: 'FavCircles Premium', what: 'Unlimited circles, your whole photo map, imports and more',
      productId: u.subscriptionProductId, status: u.subscriptionStatus, expiry: u.subscriptionExpiryDate, now }),
    appleEntry({ id: 'business', name: 'FavCircles Business', what: 'Your store page, rewards and offers',
      productId: u.ownerSubscriptionProductId, status: u.ownerSubscriptionStatus, expiry: u.ownerSubscriptionExpiryDate, now }),
    fridgeEntry(planDoc.exists ? planDoc.data() : null, now)
  ].filter(Boolean);
}

module.exports = { listSubscriptions, appleEntry, fridgeEntry };
