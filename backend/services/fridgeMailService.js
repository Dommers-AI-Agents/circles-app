// backend/services/fridgeMailService.js
// Fridge Mail: kids' drawings mailed weekly to grandparents.
// Plans + recipients here; billing (Stripe) and weekly (the send run) are mixed in from ./fridgeMail.
// Constants and pure helpers live in ./fridgeMail/shared.js.
const { COLLECTIONS, FridgeMailError, KIND, MAX_QUEUE, MAX_RECIPIENTS, NAME_MAX, NOTE_MAX, PACKS, PACK_KIND, RELATION_MAX, SUBSCRIPTION_LOOKUP_KEY, SUBSCRIPTION_PRICE_CENTS, SUB_ACTIVE, buildFridgeBackHtml, clean, defaultPlan, entitlement, getFirestore, isDue, isEnabled, localClock, newId, nowIso, postcardMailService, postcardShareService, requireEnabled, sendInBackground, stripeClient } = require('./fridgeMail/shared');

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

  /**
   * Edit a grandparent in place. The id (and createdAt) survive so the cards
   * already sent to them keep pointing at the same person; the address is
   * re-verified exactly like a new one.
   */
  async updateRecipient({ userId, recipientId, name, relation, address }) {
    requireEnabled();
    const { ref, plan } = await this.ensurePlan(userId);
    const recipients = [...(plan.recipients || [])];
    const index = recipients.findIndex((r) => r.id === recipientId);
    if (index < 0) throw new FridgeMailError(404, 'no_recipient', 'That recipient is gone already.');
    const current = recipients[index];
    const cleanName = clean(name, NAME_MAX) || current.name;
    const quote = await postcardMailService.quote({ ...(address || {}), name: cleanName });
    if (!quote.deliverable) {
      throw new FridgeMailError(422, 'undeliverable', "USPS can't deliver to that address. Check it and try again.");
    }
    recipients[index] = {
      ...current,
      name: cleanName,
      relation: relation === undefined ? current.relation : clean(relation, RELATION_MAX),
      address: {
        line1: quote.standardized.line1, line2: quote.standardized.line2 || '',
        city: quote.standardized.city, state: quote.standardized.state, zip: quote.standardized.zip
      },
      updatedAt: nowIso()
    };
    await ref.update({ recipients, updatedAt: nowIso() });
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

  // ------------------------------------------------------------- weekly

  /**
   * The daily job (15:00 UTC — before Lob's 10 AM Pacific cutoff and already
   * "today" in every US zone). Mails this week's card for every plan that is
   * due, one per recipient, as far as the entitlement goes.
   */

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
    sendInBackground(userId, { type: KIND, title, body, data }, 'fridge-mail');
  }
}

Object.assign(FridgeMailService.prototype, require('./fridgeMail/billing'), require('./fridgeMail/weekly'));
module.exports = Object.assign(new FridgeMailService(), {
  FridgeMailError, PACKS, MAX_RECIPIENTS, NOTE_MAX, SUBSCRIPTION_PRICE_CENTS, SUBSCRIPTION_LOOKUP_KEY, KIND, PACK_KIND,
  isDue, entitlement, buildFridgeBackHtml, localClock, isEnabled
});
