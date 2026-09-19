// backend/services/postcardMailService.js
// Printed-and-mailed postcards: the order state machine.
// Order CRUD + presentation here; fulfilment (release/reject/public page), reconcile (stale sweeps) and webhooks (Stripe/Lob) are mixed in from ./postcardMail.
// Constants and pure helpers live in ./postcardMail/shared.js.
const { CANCEL_WINDOW_MINUTES, COLLECTIONS, MAX_LOB_ATTEMPTS, MESSAGE_MAX_CHARS, MailError, OPEN_STATUSES, ORDER_ID_RE, STATUS, buildBackHtml, getFirestore, isEnabled, lobClient, normalizeMessage, normalizeRecipient, postcardShareService, priceCents, requireEnabled, stripeClient } = require('./postcardMail/shared');

class PostcardMailService {
  get db() { return getFirestore(); }
  get col() { return this.db.collection(COLLECTIONS.POSTCARD_ORDERS); }

  config() {
    return {
      enabled: isEnabled() && stripeClient.isEnabled() && lobClient.isEnabled(),
      priceCents: priceCents(),
      currency: 'usd',
      cancelWindowMinutes: CANCEL_WINDOW_MINUTES,
      messageMaxChars: MESSAGE_MAX_CHARS,
      countries: ['US'],
      publishableKey: stripeClient.publishableKey(),
      applePayMerchantId: process.env.APPLE_PAY_MERCHANT_ID || null,
      policyText: 'Printed and mailed by our print partner. Your card is only charged when the postcard goes to print, about an hour after you send it. Cancel free until then.'
    };
  }

  async quote(recipientInput) {
    requireEnabled();
    const recipient = normalizeRecipient(recipientInput);
    const verification = await lobClient.verifyUSAddress(recipient);
    return {
      deliverable: verification.deliverable,
      standardized: { name: recipient.name, ...verification.standardized },
      priceCents: priceCents(),
      currency: 'usd'
    };
  }

  /**
   * Writes the order and places nothing on the card yet — the authorization
   * happens on the device. Idempotent on orderId: a retried call returns the
   * same PaymentIntent rather than a second hold.
   */
  async createOrder({ userId, orderId, imageUrl, message, templateId, recipient: recipientInput, placeRef }) {
    requireEnabled();
    if (!ORDER_ID_RE.test(String(orderId || ''))) {
      throw new MailError(400, 'invalid_order_id', 'A valid orderId is required.');
    }
    if (!postcardShareService.isAllowedImageUrl(imageUrl)) {
      throw new MailError(400, 'invalid_image', 'Upload the printed postcard image first.');
    }
    const recipient = normalizeRecipient(recipientInput);
    const text = normalizeMessage(message);

    const existing = await this.col.doc(orderId).get();
    if (existing.exists) {
      const row = existing.data();
      if (row.userId !== userId) throw new MailError(403, 'not_your_order', 'That order belongs to someone else.');
      if (row.status !== STATUS.CREATED) {
        throw new MailError(409, 'already_placed', 'That order has already been placed.');
      }
      return { orderId, paymentIntentClientSecret: row.stripeClientSecret, amountCents: row.amountCents };
    }

    const amountCents = priceCents();
    const intent = await stripeClient.createAuthorization({
      orderId,
      userId,
      amountCents,
      currency: 'usd',
      description: `FavCircles printed postcard to ${recipient.name}`
    });

    const now = new Date().toISOString();
    await this.col.doc(orderId).create({
      userId,
      status: STATUS.CREATED,
      amountCents,
      currency: 'usd',
      stripePaymentIntentId: intent.id,
      stripeClientSecret: intent.client_secret,
      recipient,
      imageUrl,
      message: text,
      templateId: typeof templateId === 'string' ? templateId.slice(0, 32) : 'classic',
      placeName: placeRef?.name ? String(placeRef.name).slice(0, 120) : null,
      placeCity: placeRef?.city ? String(placeRef.city).slice(0, 80) : null,
      publicPageToken: null,
      lobPostcardId: null,
      lobExpectedDeliveryDate: null,
      lobPreviewUrl: null,
      lobAttempts: 0,
      authorizedAt: null,
      cancelableUntil: null,
      capturedAt: null,
      error: null,
      createdAt: now,
      updatedAt: now
    });

    return { orderId, paymentIntentClientSecret: intent.client_secret, amountCents };
  }

  /**
   * The device says Apple Pay succeeded. We don't take its word for it — the
   * PaymentIntent is re-read from Stripe and must actually be holding money.
   * Touches neither Lob nor the capture, so there is no money race here.
   */
  async confirmOrder({ userId, orderId }) {
    const ref = this.col.doc(orderId);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new MailError(404, 'not_found', 'That order no longer exists.');
    const row = snapshot.data();
    if (row.userId !== userId) throw new MailError(403, 'not_your_order', 'That order belongs to someone else.');
    if (row.status !== STATUS.CREATED) return this.present(orderId, row); // already authorized, or further along

    const intent = await stripeClient.getPaymentIntent(row.stripePaymentIntentId);
    if (intent.status !== 'requires_capture') {
      throw new MailError(409, 'not_authorized', 'That payment hasn\'t been authorized yet.');
    }

    const updated = await this.markAuthorized(orderId);
    return this.present(orderId, updated || row);
  }

  /**
   * created -> authorized. Shared by the client confirm and the
   * `payment_intent.amount_capturable_updated` webhook, whichever lands
   * first; the loser is a no-op.
   */
  async markAuthorized(orderId) {
    const ref = this.col.doc(orderId);
    const now = new Date();
    const patch = {
      status: STATUS.AUTHORIZED,
      authorizedAt: now.toISOString(),
      cancelableUntil: new Date(now.getTime() + CANCEL_WINDOW_MINUTES * 60000).toISOString(),
      updatedAt: now.toISOString()
    };
    const changed = await this.transition(ref, STATUS.CREATED, patch);
    if (!changed) return null;
    return { ...(await ref.get()).data() };
  }

  /**
   * Free cancel. Gated on STATUS, never on the clock: if the release job has
   * already claimed this order the card may be at the printer, and voiding
   * the hold then would mail a card nobody paid for.
   */
  async cancelOrder({ userId, orderId }) {
    const ref = this.col.doc(orderId);
    const snapshot = await ref.get();
    if (!snapshot.exists) throw new MailError(404, 'not_found', 'That order no longer exists.');
    const row = snapshot.data();
    if (row.userId !== userId) throw new MailError(403, 'not_your_order', 'That order belongs to someone else.');
    if (row.status === STATUS.CANCELED) return this.present(orderId, row);

    const now = new Date().toISOString();
    const claimed = await this.transition(ref, STATUS.AUTHORIZED, {
      status: STATUS.CANCELED,
      canceledAt: now,
      updatedAt: now
    });
    if (!claimed) {
      throw new MailError(409, 'too_late', 'That postcard is already on its way to the printer.');
    }

    // The status change is the promise; releasing the hold is bookkeeping we
    // can retry. Never leave the order authorized just because Stripe blipped.
    try {
      await stripeClient.voidAuthorization(row.stripePaymentIntentId);
    } catch (error) {
      console.error(`[postcard-mail] void failed for ${orderId}: ${error.message}`);
      await ref.update({ error: `void_failed: ${error.message}` });
    }
    return this.present(orderId, (await ref.get()).data());
  }

  async listOrders(userId, limit = 25) {
    // Fridge Mail cards share the collection but have their own history view
    const snapshot = await this.col.where('userId', '==', userId)
      .orderBy('createdAt', 'desc').limit(limit * 2).get();
    return snapshot.docs
      .filter((doc) => doc.data().kind !== 'fridgemail')
      .slice(0, limit)
      .map((doc) => this.present(doc.id, doc.data()));
  }

  async getOrder({ userId, orderId }) {
    const snapshot = await this.col.doc(orderId).get();
    if (!snapshot.exists) throw new MailError(404, 'not_found', 'That order no longer exists.');
    const row = snapshot.data();
    if (row.userId !== userId) throw new MailError(403, 'not_your_order', 'That order belongs to someone else.');
    return this.present(orderId, row);
  }

  /** Never leaks the client secret or internal error strings to the app. */
  present(orderId, row) {
    return {
      orderId,
      status: row.status,
      amountCents: row.amountCents,
      currency: row.currency,
      recipientName: row.recipient?.name || null,
      recipientCity: row.recipient?.city || null,
      recipientState: row.recipient?.state || null,
      imageUrl: row.imageUrl,
      message: row.message,
      expectedDeliveryDate: row.lobExpectedDeliveryDate || null,
      cancelableUntil: row.cancelableUntil || null,
      canCancel: row.status === STATUS.AUTHORIZED,
      publicPageUrl: row.publicPageToken ? `${postcardShareService.PUBLIC_BASE_URL}/postcard/${row.publicPageToken}` : null,
      createdAt: row.createdAt
    };
  }

  /** Compare-and-set on status. The only safe way to move money-bearing rows. */
  async transition(ref, expectedStatus, patch) {
    return this.db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      if (!fresh.exists || fresh.data().status !== expectedStatus) return false;
      tx.update(ref, patch);
      return true;
    });
  }

  // ------------------------------------------------------------- the worker

  /**
   * The release job (every 10 minutes). Cancel windows that have closed get
   * printed and charged, in that order.
   */

  /**
   * Hourly cleanup for everything the release job can't fix itself.
   */

  // ------------------------------------------------------------- webhooks

  /** Stripe's view of the truth, for when the client dies mid-flow. */
}

Object.assign(PostcardMailService.prototype, require('./postcardMail/fulfilment'), require('./postcardMail/reconcile'), require('./postcardMail/webhooks'));
module.exports = Object.assign(new PostcardMailService(), {
  MailError,
  STATUS,
  OPEN_STATUSES,
  CANCEL_WINDOW_MINUTES,
  MESSAGE_MAX_CHARS,
  MAX_LOB_ATTEMPTS,
  normalizeRecipient,
  normalizeMessage,
  buildBackHtml,
  isEnabled,
  priceCents
});
