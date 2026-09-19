// services/fridgeMail/billing.js — methods of FridgeMailService (mixed into its prototype by the facade).
const { FieldValue, FridgeMailError, KIND, ORDER_ID_RE, PACKS, PACK_KIND, SUBSCRIPTION_LOOKUP_KEY, SUBSCRIPTION_PRICE_CENTS, SUB_ACTIVE, defaultPlan, getFirestore, nowIso, requireEnabled, stripeClient } = require('./shared');

module.exports = {
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
  },

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
  },

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
  },

  /** A print failure on a prepaid card gives the credit back. */
  async refundCredit(userId, reason) {
    try {
      const { ref } = await this.ensurePlan(userId);
      await ref.update({ cardsRemaining: FieldValue.increment(1), updatedAt: nowIso() });
      console.warn(`[fridge-mail] credit returned to ${userId}: ${reason}`);
    } catch (error) {
      console.error(`[fridge-mail] credit return failed for ${userId}: ${error.message}`);
    }
  },

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
  },

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
  },

  async cancelSubscription({ userId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    if (!plan.subscription || !plan.subscription.id) throw new FridgeMailError(404, 'no_subscription', "You're not subscribed.");
    const sub = await stripeClient.cancelSubscriptionAtPeriodEnd(plan.subscription.id);
    const subscription = this.mirrorSubscription(sub);
    await ref.update({ subscription, updatedAt: nowIso() });
    return this.present({ ...plan, subscription });
  },

  async resumeSubscription({ userId }) {
    const { ref, plan } = await this.ensurePlan(userId);
    if (!plan.subscription || !plan.subscription.id) throw new FridgeMailError(404, 'no_subscription', "You're not subscribed.");
    const sub = await stripeClient.resumeSubscription(plan.subscription.id);
    const subscription = this.mirrorSubscription(sub);
    await ref.update({ subscription, updatedAt: nowIso() });
    return this.present({ ...plan, subscription });
  },

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
  },

  async planByCustomer(customerId) {
    if (!customerId) return null;
    const snap = await this.plans.where('stripeCustomerId', '==', customerId).limit(1).get();
    return snap.empty ? null : snap.docs[0];
  },

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
  },
};
