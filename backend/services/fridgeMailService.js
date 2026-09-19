// backend/services/fridgeMailService.js
// Fridge Mail: a parent queues kids' drawings and photos, names 1–3 recipients
// (grandparents, verified US addresses), and every week we mail one printed
// postcard per recipient, automatically. Paid up front: prepaid card packs
// (one Apple Pay charge) or a monthly subscription (a card saved through a
// SetupIntent, billed by Stripe per recipient).
//
// What is reused: Lob printing and delivery tracking, the print-image upload,
// address verification and the Apple Pay bridge all come from the printed
// postcard feature. A mailed Fridge Mail card is a `postcardOrders` row with
// `kind: 'fridgemail'` and `prepaid: true` — no Stripe intent, `capturedAt`
// stays null, and the postcard reconciler/unwind paths skip the money steps
// for it. A print failure gives a credit back, never a Stripe refund.
const crypto = require('crypto');
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const stripeClient = require('./stripeClient');
const lobClient = require('./lobClient');
const postcardMailService = require('./postcardMailService');
const postcardShareService = require('./postcardShareService');
const notificationService = require('./notificationService');

const KIND = 'fridgemail';
const PACK_KIND = 'fridgemail_pack';
const SUBSCRIPTION_LOOKUP_KEY = 'fridgemail_monthly';
const SUBSCRIPTION_PRICE_CENTS = 799; // per recipient per month, 1 card a week

const PACKS = [
  { id: 'pack5', cards: 5, amountCents: 1299, label: '5 cards' },
  { id: 'pack12', cards: 12, amountCents: 2499, label: '12 cards' },
  { id: 'pack26', cards: 26, amountCents: 4999, label: '26 cards' }
];

const MAX_RECIPIENTS = 3;
const MAX_QUEUE = 300;
const NAME_MAX = 40;
const NOTE_MAX = 200;
const RELATION_MAX = 30;
// Rolling window instead of ISO-week math (the weekly summary learned this):
// a plan sends again once six days have passed since its last card.
const RESEND_AFTER_MS = 6 * 24 * 60 * 60 * 1000;
const ORDER_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const SUB_ACTIVE = new Set(['active', 'trialing']);

class FridgeMailError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}

const isEnabled = () => process.env.POSTCARD_MAIL_ENABLED === '1';
const dryRun = () => process.env.FRIDGEMAIL_DRY_RUN === '1';
const nowIso = () => new Date().toISOString();
const newId = () => crypto.randomBytes(9).toString('base64url');

function requireEnabled() {
  if (!isEnabled()) throw new FridgeMailError(503, 'mail_disabled', "Fridge Mail isn't available yet.");
  if (!stripeClient.isEnabled() || !lobClient.isEnabled()) {
    throw new FridgeMailError(503, 'mail_unconfigured', "Fridge Mail isn't available yet.");
  }
}

const clean = (value, max) => String(value || '').trim().slice(0, max);

/** { hour, weekday (0 = Sunday) } in an IANA zone, New York when unknown. */
function localClock(timeZone, now) {
  const read = (zone) => {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, hour: 'numeric', hour12: false, weekday: 'short' }).formatToParts(now);
    const hour = parseInt(parts.find((p) => p.type === 'hour').value, 10) % 24;
    const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(parts.find((p) => p.type === 'weekday').value);
    return { hour, weekday };
  };
  try { return read(timeZone || 'America/New_York'); } catch (error) { return read('America/New_York'); }
}

function formatLongDate(now, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone: timeZone || 'America/New_York', month: 'long', day: 'numeric', year: 'numeric' }).format(now);
  } catch (error) {
    return new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric' }).format(now);
  }
}

const escapeHtml = (s) => String(s || '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/**
 * The back of a Fridge Mail card. Same page geometry as the postcard back
 * (Lob's USPS block sits bottom-right: 3.2835in x 2.375in, 0.275in from the
 * right, 0.25in from the bottom). Big, warm, readable on a fridge: who, when,
 * the note, and who it's from. No QR — grandma isn't scanning anything.
 */
function buildFridgeBackHtml({ childName, ageText, dateText, note, familyName }) {
  const who = [clean(childName, NAME_MAX), clean(ageText, 20)].filter(Boolean).join(', ');
  return `<html><head><meta charset="utf-8"><style>
  @page { size: 6.25in 4.25in; margin: 0; }
  body { width: 6.25in; height: 4.25in; margin: 0; font-family: Georgia, 'Times New Roman', serif; color: #1a202c; }
  .who { position: absolute; top: 0.4in; left: 0.4in; width: 2.7in; font-size: 15pt; font-weight: bold; line-height: 1.25; }
  .when { position: absolute; top: 0.85in; left: 0.4in; width: 2.7in; font-size: 9.5pt; color: #4a5568; font-family: Helvetica, Arial, sans-serif; }
  .note { position: absolute; top: 1.25in; left: 0.4in; width: 2.7in; height: 2.1in; font-size: 12pt; line-height: 1.45; overflow: hidden; white-space: pre-wrap; }
  .from { position: absolute; top: 3.55in; left: 0.4in; width: 2.7in; font-size: 10pt; color: #2d3748; }
  .brand { position: absolute; top: 0.4in; right: 0.4in; width: 2.9in; text-align: right; font-size: 7.5pt; letter-spacing: .06em; text-transform: uppercase; color: #a0aec0; font-family: Helvetica, Arial, sans-serif; }
</style></head><body>
  <div class="brand">Fridge Mail · FavCircles</div>
  <div class="who">${escapeHtml(who)}</div>
  <div class="when">${escapeHtml(dateText)}</div>
  <div class="note">${escapeHtml(clean(note, NOTE_MAX))}</div>
  <div class="from">— From ${escapeHtml(clean(familyName, 60) || 'the family')}</div>
</body></html>`;
}

function defaultPlan(userId) {
  const now = nowIso();
  return {
    userId,
    familyName: '',
    recipients: [],
    queue: [],
    weekday: 1, // Monday
    timezone: 'America/New_York',
    status: 'active',
    cardsRemaining: 0,
    stripeCustomerId: null,
    subscription: null,
    lastSentAt: null,
    lastNudgeAt: null,
    createdAt: now,
    updatedAt: now
  };
}

/**
 * Pure: is this plan due to send right now? Local weekday must match and the
 * last card must be at least six days old. Evaluated by a job that runs
 * once a day (15:00 UTC), so "the hour" is never part of the rule.
 */
function isDue(plan, now = new Date()) {
  if (!plan || plan.status !== 'active') return false;
  const { weekday } = localClock(plan.timezone, now);
  if (weekday !== (Number.isInteger(plan.weekday) ? plan.weekday : 1)) return false;
  if (!plan.lastSentAt) return true;
  return now.getTime() - Date.parse(plan.lastSentAt) >= RESEND_AFTER_MS;
}

/** How many recipients this week's run can pay for, and from what. */
function entitlement(plan) {
  const recipients = (plan.recipients || []).length;
  const sub = plan.subscription;
  const subscribedSlots = sub && SUB_ACTIVE.has(sub.status) ? Math.min(recipients, sub.quantity || 0) : 0;
  const credits = Math.max(0, plan.cardsRemaining || 0);
  const covered = Math.min(recipients, subscribedSlots + credits);
  const creditsNeededPerWeek = Math.max(0, recipients - subscribedSlots);
  const weeksOfCredits = creditsNeededPerWeek > 0 ? Math.floor(credits / creditsNeededPerWeek) : null;
  return { recipients, subscribedSlots, credits, covered, creditsNeededPerWeek, weeksOfCredits };
}

class FridgeMailService {
  get plans() { return getFirestore().collection(COLLECTIONS.FRIDGE_MAIL_PLANS); }
  get packOrders() { return getFirestore().collection(COLLECTIONS.FRIDGE_MAIL_PACK_ORDERS); }
  get cards() { return getFirestore().collection(COLLECTIONS.POSTCARD_ORDERS); }

  // ------------------------------------------------------------- plan

  async ensurePlan(userId) {
    const ref = this.plans.doc(userId);
    const snap = await ref.get();
    if (snap.exists) return { ref, plan: snap.data() };
    const plan = defaultPlan(userId);
    try { await ref.create(plan); } catch (error) { /* raced: read it back */ }
    const again = await ref.get();
    return { ref, plan: again.exists ? again.data() : plan };
  }

  async getPlan(userId) {
    const { plan } = await this.ensurePlan(userId);
    return this.present(plan);
  }

  present(plan, now = new Date()) {
    const ent = entitlement(plan);
    return {
      familyName: plan.familyName || '',
      recipients: (plan.recipients || []).map((r) => ({
        id: r.id, name: r.name, relation: r.relation || '', address: r.address
      })),
      queue: (plan.queue || []).map((q) => ({
        id: q.id, imageUrl: q.imageUrl, childName: q.childName, ageText: q.ageText || '', note: q.note || '',
        addedAt: q.addedAt, sentAt: q.sentAt || null
      })),
      weekday: Number.isInteger(plan.weekday) ? plan.weekday : 1,
      timezone: plan.timezone || 'America/New_York',
      status: plan.status || 'active',
      cardsRemaining: plan.cardsRemaining || 0,
      subscription: plan.subscription ? {
        status: plan.subscription.status,
        quantity: plan.subscription.quantity || 0,
        currentPeriodEnd: plan.subscription.currentPeriodEnd || null,
        cancelAtPeriodEnd: !!plan.subscription.cancelAtPeriodEnd
      } : null,
      lastSentAt: plan.lastSentAt || null,
      nextSendAt: this.nextSendAt(plan, now),
      entitlement: {
        covered: ent.covered,
        recipients: ent.recipients,
        subscribedSlots: ent.subscribedSlots,
        weeksOfCredits: ent.weeksOfCredits
      },
      packs: PACKS,
      subscriptionPriceCents: SUBSCRIPTION_PRICE_CENTS,
      currency: 'usd'
    };
  }

  /** The next daily run (15:00 UTC) on which `isDue` will be true. */
  nextSendAt(plan, now = new Date()) {
    if (plan.status !== 'active') return null;
    for (let day = 0; day < 8; day++) {
      const candidate = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + day, 15, 0, 0));
      if (candidate <= now) continue;
      if (isDue({ ...plan }, candidate)) return candidate.toISOString();
    }
    return null;
  }

  async setPlan({ userId, weekday, timezone, familyName, status }) {
    const { ref, plan } = await this.ensurePlan(userId);
    const patch = { updatedAt: nowIso() };
    if (weekday !== undefined) {
      const w = Number(weekday);
      if (!Number.isInteger(w) || w < 0 || w > 6) throw new FridgeMailError(400, 'bad_weekday', 'Pick a day of the week.');
      patch.weekday = w;
    }
    if (timezone !== undefined) {
      try { new Intl.DateTimeFormat('en-US', { timeZone: timezone }); } catch (error) {
        throw new FridgeMailError(400, 'bad_timezone', "That timezone isn't recognized.");
      }
      patch.timezone = timezone;
    }
    if (familyName !== undefined) patch.familyName = clean(familyName, 60);
    if (status !== undefined) {
      if (!['active', 'paused'].includes(status)) throw new FridgeMailError(400, 'bad_status', 'Status must be active or paused.');
      patch.status = status;
    }
    await ref.update(patch);
    return this.present({ ...plan, ...patch });
  }

  // ------------------------------------------------------------ recipients

  async addRecipient({ userId, name, relation, address }) {
    requireEnabled();
    const { ref, plan } = await this.ensurePlan(userId);
    if ((plan.recipients || []).length >= MAX_RECIPIENTS) {
      throw new FridgeMailError(400, 'too_many_recipients', `Fridge Mail can go to up to ${MAX_RECIPIENTS} people.`);
    }
    // Verified against Lob (the postcard quote) — a card to a bad address is a
    // card in the trash.
    const quote = await postcardMailService.quote({ ...(address || {}), name: clean(name, NAME_MAX) || 'Recipient' });
    if (!quote.deliverable) {
      throw new FridgeMailError(422, 'undeliverable', "USPS can't deliver to that address. Check it and try again.");
    }
    const recipient = {
      id: newId(),
      name: clean(name, NAME_MAX) || quote.standardized.name,
      relation: clean(relation, RELATION_MAX),
      address: {
        line1: quote.standardized.line1, line2: quote.standardized.line2 || '',
        city: quote.standardized.city, state: quote.standardized.state, zip: quote.standardized.zip
      },
      createdAt: nowIso()
    };
    const recipients = [...(plan.recipients || []), recipient];
    await ref.update({ recipients, updatedAt: nowIso() });
    await this.syncSubscriptionQuantity({ ...plan, recipients });
    return this.present({ ...plan, recipients });
  }

  async removeRecipient({ userId, recipientId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    const recipients = (plan.recipients || []).filter((r) => r.id !== recipientId);
    if (recipients.length === (plan.recipients || []).length) throw new FridgeMailError(404, 'no_recipient', 'That recipient is gone already.');
    await ref.update({ recipients, updatedAt: nowIso() });
    await this.syncSubscriptionQuantity({ ...plan, recipients });
    return this.present({ ...plan, recipients });
  }

  /** Recipient count → subscription quantity, no proration (see plan notes). */
  async syncSubscriptionQuantity(plan) {
    const sub = plan.subscription;
    if (!sub || !sub.id || !SUB_ACTIVE.has(sub.status)) return;
    const quantity = Math.max(1, (plan.recipients || []).length);
    if (quantity === sub.quantity) return;
    try {
      await stripeClient.updateSubscriptionQuantity({ subscriptionId: sub.id, quantity });
      await this.plans.doc(plan.userId).update({ 'subscription.quantity': quantity, updatedAt: nowIso() });
    } catch (error) {
      console.error(`[fridge-mail] quantity sync failed for ${plan.userId}: ${error.message}`);
    }
  }

  // ---------------------------------------------------------------- queue

  async enqueue({ userId, imageUrl, childName, ageText, note }) {
    const { ref, plan } = await this.ensurePlan(userId);
    if (!postcardShareService.isAllowedImageUrl(imageUrl)) {
      throw new FridgeMailError(400, 'bad_image', 'Upload the drawing first.');
    }
    if ((plan.queue || []).length >= MAX_QUEUE) throw new FridgeMailError(400, 'queue_full', 'The queue is full.');
    const item = {
      id: newId(), imageUrl, childName: clean(childName, NAME_MAX), ageText: clean(ageText, 20), note: clean(note, NOTE_MAX),
      addedAt: nowIso(), sentAt: null
    };
    const queue = [...(plan.queue || []), item];
    await ref.update({ queue, updatedAt: nowIso() });
    return this.present({ ...plan, queue });
  }

  async removeQueued({ userId, itemId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    const item = (plan.queue || []).find((q) => q.id === itemId);
    if (!item) throw new FridgeMailError(404, 'no_item', 'That drawing is gone already.');
    if (item.sentAt) throw new FridgeMailError(409, 'already_sent', 'That one has already been mailed.');
    const queue = plan.queue.filter((q) => q.id !== itemId);
    await ref.update({ queue, updatedAt: nowIso() });
    return this.present({ ...plan, queue });
  }

  /** Reorders the UNSENT items; sent history keeps its order. */
  async reorderQueue({ userId, ids }) {
    const { ref, plan } = await this.ensurePlan(userId);
    const queue = plan.queue || [];
    const sent = queue.filter((q) => q.sentAt);
    const pending = queue.filter((q) => !q.sentAt);
    const byId = new Map(pending.map((q) => [q.id, q]));
    const ordered = (ids || []).map((id) => byId.get(id)).filter(Boolean);
    const rest = pending.filter((q) => !ids.includes(q.id));
    const next = [...sent, ...ordered, ...rest];
    await ref.update({ queue: next, updatedAt: nowIso() });
    return this.present({ ...plan, queue: next });
  }

  // ---------------------------------------------------------------- packs

  packs() { return PACKS; }

  async createPackOrder({ userId, orderId, packId }) {
    requireEnabled();
    if (!ORDER_ID_RE.test(String(orderId || ''))) throw new FridgeMailError(400, 'bad_order_id', 'Order id is malformed.');
    const pack = PACKS.find((p) => p.id === packId);
    if (!pack) throw new FridgeMailError(400, 'bad_pack', 'Pick a card pack.');
    const ref = this.packOrders.doc(orderId);
    const existing = await ref.get();
    if (existing.exists) {
      const row = existing.data();
      if (row.userId !== userId) throw new FridgeMailError(403, 'not_your_order', 'Not your order.');
      return { orderId, paymentIntentClientSecret: row.stripeClientSecret, amountCents: row.amountCents, cards: row.cards };
    }
    const intent = await stripeClient.createPayment({
      orderId, userId, amountCents: pack.amountCents, description: `FavCircles Fridge Mail — ${pack.label}`, kind: PACK_KIND
    });
    await ref.create({
      userId, packId: pack.id, cards: pack.cards, amountCents: pack.amountCents, currency: 'usd',
      stripePaymentIntentId: intent.id, stripeClientSecret: intent.client_secret,
      status: 'created', createdAt: nowIso(), paidAt: null, updatedAt: nowIso()
    });
    return { orderId, paymentIntentClientSecret: intent.client_secret, amountCents: pack.amountCents, cards: pack.cards };
  }

  async confirmPackOrder({ userId, orderId }) {
    const ref = this.packOrders.doc(orderId);
    const snap = await ref.get();
    if (!snap.exists) throw new FridgeMailError(404, 'no_order', 'No such order.');
    const row = snap.data();
    if (row.userId !== userId) throw new FridgeMailError(403, 'not_your_order', 'Not your order.');
    const intent = await stripeClient.getPaymentIntent(row.stripePaymentIntentId);
    if (intent.status !== 'succeeded') throw new FridgeMailError(409, 'not_paid', "The payment hasn't gone through yet.");
    await this.creditPack(orderId);
    return this.getPlan(userId);
  }

  /** Credits a paid pack exactly once (compare-and-set inside a transaction). */
  async creditPack(orderId) {
    const db = getFirestore();
    const orderRef = this.packOrders.doc(orderId);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(orderRef);
      if (!snap.exists) return { credited: false, reason: 'no_order' };
      const row = snap.data();
      if (row.status === 'paid') return { credited: false, reason: 'already' };
      const planRef = this.plans.doc(row.userId);
      const planSnap = await tx.get(planRef);
      const ts = nowIso();
      if (planSnap.exists) {
        tx.update(planRef, { cardsRemaining: FieldValue.increment(row.cards), updatedAt: ts });
      } else {
        tx.set(planRef, { ...defaultPlan(row.userId), cardsRemaining: row.cards });
      }
      tx.update(orderRef, { status: 'paid', paidAt: ts, updatedAt: ts });
      return { credited: true, cards: row.cards };
    });
  }

  /** A print failure on a prepaid card gives the credit back. */
  async refundCredit(userId, reason) {
    try {
      const { ref } = await this.ensurePlan(userId);
      await ref.update({ cardsRemaining: FieldValue.increment(1), updatedAt: nowIso() });
      console.warn(`[fridge-mail] credit returned to ${userId}: ${reason}`);
    } catch (error) {
      console.error(`[fridge-mail] credit return failed for ${userId}: ${error.message}`);
    }
  }

  // --------------------------------------------------------- subscription

  async setupSubscription({ userId, email, name }) {
    requireEnabled();
    const { ref, plan } = await this.ensurePlan(userId);
    if (plan.subscription && SUB_ACTIVE.has(plan.subscription.status)) {
      throw new FridgeMailError(409, 'already_subscribed', "You're already subscribed.");
    }
    const customer = await stripeClient.ensureCustomer({ existingId: plan.stripeCustomerId, userId, email, name });
    if (customer.id !== plan.stripeCustomerId) await ref.update({ stripeCustomerId: customer.id, updatedAt: nowIso() });
    const intent = await stripeClient.createSetupIntent({ customerId: customer.id, userId, kind: KIND });
    return { setupIntentId: intent.id, setupIntentClientSecret: intent.client_secret,
             priceCents: SUBSCRIPTION_PRICE_CENTS, quantity: Math.max(1, (plan.recipients || []).length) };
  }

  async startSubscription({ userId, setupIntentId }) {
    requireEnabled();
    const { ref, plan } = await this.ensurePlan(userId);
    if (plan.subscription && SUB_ACTIVE.has(plan.subscription.status)) return this.present(plan);
    const intent = await stripeClient.getSetupIntent(setupIntentId);
    if (!intent || intent.status !== 'succeeded') throw new FridgeMailError(409, 'card_not_saved', "The card wasn't saved. Try again.");
    if (plan.stripeCustomerId && intent.customer !== plan.stripeCustomerId) {
      throw new FridgeMailError(403, 'not_your_intent', 'That card belongs to a different account.');
    }
    const price = await stripeClient.priceByLookupKey(SUBSCRIPTION_LOOKUP_KEY);
    if (!price) throw new FridgeMailError(503, 'no_price', "Subscriptions aren't set up yet.");
    const paymentMethodId = typeof intent.payment_method === 'string' ? intent.payment_method : intent.payment_method.id;
    await stripeClient.setDefaultPaymentMethod({ customerId: intent.customer, paymentMethodId });
    const quantity = Math.max(1, (plan.recipients || []).length);
    let sub;
    try {
      sub = await stripeClient.createSubscription({ customerId: intent.customer, priceId: price.id, quantity, paymentMethodId, userId, kind: KIND });
    } catch (error) {
      throw new FridgeMailError(402, 'payment_failed', error.message || 'The first payment failed.');
    }
    const subscription = this.mirrorSubscription(sub);
    await ref.update({ subscription, stripeCustomerId: intent.customer, updatedAt: nowIso() });
    return this.present({ ...plan, subscription, stripeCustomerId: intent.customer });
  }

  async cancelSubscription({ userId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    if (!plan.subscription || !plan.subscription.id) throw new FridgeMailError(404, 'no_subscription', "You're not subscribed.");
    const sub = await stripeClient.cancelSubscriptionAtPeriodEnd(plan.subscription.id);
    const subscription = this.mirrorSubscription(sub);
    await ref.update({ subscription, updatedAt: nowIso() });
    return this.present({ ...plan, subscription });
  }

  async resumeSubscription({ userId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    if (!plan.subscription || !plan.subscription.id) throw new FridgeMailError(404, 'no_subscription', "You're not subscribed.");
    const sub = await stripeClient.resumeSubscription(plan.subscription.id);
    const subscription = this.mirrorSubscription(sub);
    await ref.update({ subscription, updatedAt: nowIso() });
    return this.present({ ...plan, subscription });
  }

  /** What we keep from a Stripe subscription object. */
  mirrorSubscription(sub) {
    const item = sub.items && sub.items.data && sub.items.data[0];
    const periodEnd = sub.current_period_end || (item && item.current_period_end) || null;
    return {
      id: sub.id,
      status: sub.status,
      quantity: item ? item.quantity : (sub.quantity || 1),
      currentPeriodEnd: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
      cancelAtPeriodEnd: !!sub.cancel_at_period_end
    };
  }

  async planByCustomer(customerId) {
    if (!customerId) return null;
    const snap = await this.plans.where('stripeCustomerId', '==', customerId).limit(1).get();
    return snap.empty ? null : snap.docs[0];
  }

  /** Stripe's view of the truth. Only events the router already attributed to us. */
  async handleStripeEvent(event) {
    const obj = event && event.data && event.data.object;
    if (!obj) return { ignored: true };
    switch (event.type) {
      case 'payment_intent.succeeded': {
        if (obj.metadata && obj.metadata.kind === PACK_KIND && obj.metadata.orderId) {
          return { handled: 'pack', ...(await this.creditPack(obj.metadata.orderId)) };
        }
        return { ignored: true };
      }
      case 'invoice.paid':
      case 'invoice.payment_failed': {
        const doc = await this.planByCustomer(obj.customer);
        if (!doc) return { ignored: true };
        const subId = typeof obj.subscription === 'string' ? obj.subscription : (obj.subscription && obj.subscription.id);
        if (!subId) return { ignored: true };
        const sub = await stripeClient.getSubscription(subId);
        const subscription = this.mirrorSubscription(sub);
        await doc.ref.update({ subscription, updatedAt: nowIso() });
        if (event.type === 'invoice.payment_failed') {
          this.notify(doc.id, {
            title: 'Fridge Mail payment didn\'t go through',
            body: 'Update your card in the Fridge Mail widget so the postcards keep coming.',
            data: { reason: 'payment_failed' }
          });
        }
        return { handled: event.type };
      }
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const doc = await this.planByCustomer(obj.customer);
        if (!doc) return { ignored: true };
        const subscription = this.mirrorSubscription(obj);
        await doc.ref.update({ subscription, updatedAt: nowIso() });
        return { handled: event.type };
      }
      default:
        return { ignored: true };
    }
  }

  // ------------------------------------------------------------- weekly

  /**
   * The daily job (15:00 UTC — before Lob's 10 AM Pacific cutoff and already
   * "today" in every US zone). Mails this week's card for every plan that is
   * due, one per recipient, as far as the entitlement goes.
   */
  async runWeekly({ now = new Date(), limit = 200 } = {}) {
    const summary = { plans: 0, sent: 0, skippedNoQueue: 0, skippedNoCredit: 0, failed: 0 };
    if (!isEnabled() || !lobClient.isEnabled()) return { ...summary, disabled: true };
    // `limit` is a page size, not a cap: every active plan is visited. (It
    // used to be a cap applied before the due check, so past 200 plans the
    // rest silently never mailed.) A retried run is safe: lastSentAt gates.
    let cursor = null;
    for (;;) {
      let query = this.plans.where('status', '==', 'active').limit(limit);
      if (cursor) query = query.startAfter(cursor);
      const snap = await query.get();
      for (const doc of snap.docs) {
        const plan = doc.data();
        if (!isDue(plan, now)) continue;
        summary.plans++;
        const outcome = await this.sendForPlan(doc, plan, now);
        summary.sent += outcome.sent;
        if (outcome.reason === 'no_queue') summary.skippedNoQueue++;
        if (outcome.reason === 'no_credit') summary.skippedNoCredit++;
        summary.failed += outcome.failed;
      }
      if (snap.docs.length < limit) break;
      cursor = snap.docs[snap.docs.length - 1];
    }
    return summary;
  }

  async sendForPlan(doc, plan, now) {
    const result = { sent: 0, failed: 0, reason: null };
    const recipients = plan.recipients || [];
    const item = (plan.queue || []).find((q) => !q.sentAt);
    const weekNudgeDue = !plan.lastNudgeAt || now.getTime() - Date.parse(plan.lastNudgeAt) >= RESEND_AFTER_MS;

    if (recipients.length === 0) return { ...result, reason: 'no_recipients' };
    if (!item) {
      if (weekNudgeDue) {
        this.notify(plan.userId, {
          title: 'Fridge Mail needs a drawing',
          body: "Nothing is queued for this week. Add one and it goes out on the next mailing day.",
          data: { reason: 'no_queue' }
        });
        await doc.ref.update({ lastNudgeAt: now.toISOString() });
      }
      return { ...result, reason: 'no_queue' };
    }

    const ent = entitlement(plan);
    if (ent.covered === 0) {
      if (weekNudgeDue) {
        this.notify(plan.userId, {
          title: 'Fridge Mail is out of cards',
          body: `Add a pack or subscribe to keep ${item.childName ? `${item.childName}'s` : 'the'} drawings going to ${recipients.length === 1 ? recipients[0].name : `${recipients.length} people`}.`,
          data: { reason: 'no_credit' }
        });
        await doc.ref.update({ lastNudgeAt: now.toISOString() });
      }
      return { ...result, reason: 'no_credit' };
    }

    // Subscription slots first, then credits. Recipients past the covered
    // count wait for more cards.
    let creditsToSpend = Math.max(0, ent.covered - ent.subscribedSlots);
    const covered = recipients.slice(0, ent.covered);
    const dateText = formatLongDate(now, plan.timezone);
    for (const recipient of covered) {
      const usesCredit = creditsToSpend > 0 && covered.indexOf(recipient) >= ent.subscribedSlots;
      const ok = await this.mailOne({ plan, item, recipient, now, dateText, usesCredit });
      if (ok) {
        result.sent++;
        if (usesCredit) { creditsToSpend--; await doc.ref.update({ cardsRemaining: FieldValue.increment(-1) }); }
      } else {
        result.failed++;
      }
    }
    if (result.sent > 0) {
      const queue = (plan.queue || []).map((q) => (q.id === item.id ? { ...q, sentAt: now.toISOString() } : q));
      await doc.ref.update({ queue, lastSentAt: now.toISOString(), updatedAt: now.toISOString() });
      const to = covered.length === 1 ? covered[0].name : `${covered.length} people`;
      this.notify(plan.userId, {
        title: 'Fridge Mail is on its way',
        body: `${item.childName ? `${item.childName}'s` : 'This week\'s'} card is headed to ${to}. Typically arrives in 4 to 6 business days.`,
        data: { reason: 'sent' }
      });
      if (ent.weeksOfCredits !== null && ent.weeksOfCredits - 1 <= 1 && ent.subscribedSlots < recipients.length) {
        this.notify(plan.userId, {
          title: 'Fridge Mail is almost out of cards',
          body: ent.weeksOfCredits - 1 <= 0 ? 'That was the last prepaid card. Add a pack or subscribe to keep going.' : 'One more week of cards left. Add a pack or subscribe.',
          data: { reason: 'low_credit' }
        });
      }
    }
    return result;
  }

  /** One card to one recipient: a prepaid postcardOrders row, then Lob. */
  async mailOne({ plan, item, recipient, now, dateText, usesCredit }) {
    const rowId = `fm_${newId()}`;
    const ref = this.cards.doc(rowId);
    const row = {
      kind: KIND, prepaid: true, usesCredit: !!usesCredit,
      userId: plan.userId, status: 'submitting',
      amountCents: 0, currency: 'usd', stripePaymentIntentId: null, stripeClientSecret: null,
      recipient: { name: recipient.name, ...recipient.address },
      recipientId: recipient.id, queueItemId: item.id,
      imageUrl: item.imageUrl, message: item.note || '', childName: item.childName || '',
      templateId: KIND, placeName: null, placeCity: null, publicPageToken: null,
      lobPostcardId: null, lobExpectedDeliveryDate: null, lobPreviewUrl: null, lobAttempts: 1,
      authorizedAt: null, cancelableUntil: null, capturedAt: null, error: null,
      createdAt: now.toISOString(), updatedAt: now.toISOString()
    };
    await ref.create(row);
    try {
      let lob;
      if (dryRun()) {
        lob = { id: `dryrun_${rowId}`, expectedDeliveryDate: null, previewUrl: null };
      } else {
        lob = await lobClient.createPostcard({
          idempotencyKey: rowId,
          description: `FavCircles Fridge Mail ${rowId}`,
          to: {
            name: recipient.name,
            address_line1: recipient.address.line1,
            address_line2: recipient.address.line2 || '',
            address_city: recipient.address.city,
            address_state: recipient.address.state,
            address_zip: recipient.address.zip,
            address_country: 'US'
          },
          frontUrl: item.imageUrl,
          backHtml: buildFridgeBackHtml({
            childName: item.childName, ageText: item.ageText, dateText, note: item.note, familyName: plan.familyName
          })
        });
      }
      await ref.update({
        status: 'submitted', lobPostcardId: lob.id, lobExpectedDeliveryDate: lob.expectedDeliveryDate || null,
        lobPreviewUrl: lob.previewUrl || null, updatedAt: nowIso()
      });
      return true;
    } catch (error) {
      console.error(`[fridge-mail] Lob refused ${rowId} for ${plan.userId}: ${error.message}`);
      await ref.update({ status: 'rejected', error: String(error.message || error).slice(0, 300), needsReview: true, updatedAt: nowIso() });
      return false;
    }
  }

  async listCards(userId, limit = 60) {
    // Index (userId, kind, createdAt desc): fridge cards share postcardOrders
    // with ordinary postcards, and filtering in memory after a capped read
    // hid the fridge list behind 60 recent postcards.
    const snap = await this.cards.where('userId', '==', userId).where('kind', '==', KIND).orderBy('createdAt', 'desc').limit(limit).get();
    return snap.docs
      .map((d) => {
        const r = d.data();
        return {
          cardId: d.id, status: r.status, recipientId: r.recipientId || null, recipientName: r.recipient ? r.recipient.name : null,
          childName: r.childName || '', note: r.message || '', imageUrl: r.imageUrl,
          expectedDeliveryDate: r.lobExpectedDeliveryDate || null, lobLastEvent: r.lobLastEvent || null, createdAt: r.createdAt
        };
      });
  }

  notify(userId, { title, body, data }) {
    Promise.resolve(notificationService.sendToUser(userId, {
      type: KIND, title, body, data: { type: KIND, ...(data || {}) }
    })).catch((error) => console.error(`[fridge-mail] push failed for ${userId}: ${error.message}`));
  }
}

module.exports = Object.assign(new FridgeMailService(), {
  FridgeMailError, PACKS, MAX_RECIPIENTS, NOTE_MAX, SUBSCRIPTION_PRICE_CENTS, SUBSCRIPTION_LOOKUP_KEY, KIND, PACK_KIND,
  isDue, entitlement, buildFridgeBackHtml, localClock, isEnabled
});
