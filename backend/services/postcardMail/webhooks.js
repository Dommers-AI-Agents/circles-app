// services/postcardMail/webhooks.js — methods of PostcardMailService (mixed into its prototype by the facade).
const { STATUS, stripeClient } = require('./shared');

module.exports = {
  async handleStripeEvent(event) {
    const orderId = event?.data?.object?.metadata?.orderId;
    if (!orderId) return { ignored: true };

    switch (event.type) {
      case 'payment_intent.amount_capturable_updated':
        // Under manual capture this, not `succeeded`, is "the hold is in
        // place". No-op when the client's confirm already landed.
        await this.markAuthorized(orderId);
        return { handled: 'authorized' };

      case 'payment_intent.canceled': {
        const ref = this.col.doc(orderId);
        await this.transition(ref, STATUS.AUTHORIZED, {
          status: STATUS.EXPIRED, error: 'authorization_canceled', updatedAt: new Date().toISOString()
        });
        return { handled: 'canceled' };
      }

      case 'charge.refunded':
        await this.col.doc(orderId).update({
          status: STATUS.REFUNDED, refundedAt: new Date().toISOString(), updatedAt: new Date().toISOString()
        }).catch(() => {});
        return { handled: 'refunded' };

      default:
        return { ignored: true };
    }
  },

  /**
   * Lob delivery tracking. Purely informational — no money moves here.
   *
   * Note the event vocabulary: Lob's postcard events are mailed, in_transit,
   * in_local_area, processed_for_delivery, re-routed and returned_to_sender.
   * USPS does not scan First Class postcards on delivery, so
   * `processed_for_delivery` ("loaded on the delivery vehicle") is the
   * terminal event in practice. Treating it as anything less would leave
   * every order stuck in transit forever. `postcard.delivered` is still
   * mapped in case Lob ever emits it.
   */
  async handleLobEvent(event) {
    const lobId = event?.body?.id || event?.object_id;
    const type = event?.event_type?.id || event?.event_type;
    if (!lobId || !type) return { ignored: true };

    // Lob has rendered the card: every asset resolved, nothing left that can
    // refuse it for free. This is when the money moves.
    const RENDERED = ['postcard.rendered_pdf', 'postcard.rendered_thumbnails'];
    const TERMINAL = ['postcard.processed_for_delivery', 'postcard.delivered'];
    const IN_TRANSIT = ['postcard.mailed', 'postcard.in_transit', 'postcard.in_local_area', 'postcard.re-routed'];
    // Lob accepted the card over the API and then refused the mailpiece.
    // Before rendered_pdf the hold is still open and voiding is free; after
    // it (rare — a refusal at the print line) the money was captured and
    // only a refund puts it right.
    const PRINT_FAILED = ['postcard.failed', 'postcard.rejected'];

    if (!RENDERED.includes(type) && !TERMINAL.includes(type) && !IN_TRANSIT.includes(type)
        && !PRINT_FAILED.includes(type) && type !== 'postcard.returned_to_sender') {
      return { ignored: true };
    }

    const snapshot = await this.col.where('lobPostcardId', '==', lobId).limit(1).get();
    if (snapshot.empty) return { ignored: true };
    const doc = snapshot.docs[0];
    const row = doc.data();

    if (PRINT_FAILED.includes(type)) {
      return this.unwindPrintFailure(doc, row, type);
    }

    if (RENDERED.includes(type)) {
      if (row.capturedAt) return { handled: 'already_captured' };
      const captured = await this.captureAfterRender(doc.ref, row, type);
      return { handled: captured ? 'captured' : 'capture_pending' };
    }

    const patch = { updatedAt: new Date().toISOString(), lobLastEvent: type };
    if (TERMINAL.includes(type)) {
      patch.status = STATUS.DELIVERED;
    } else if (IN_TRANSIT.includes(type)) {
      patch.status = STATUS.IN_TRANSIT;
    } else {
      // The card came back. Not a refund decision we make automatically, but
      // never silent either — someone should look.
      patch.status = STATUS.RETURNED;
      patch.needsReview = true;
      console.warn(`[postcard-mail] Lob postcard ${lobId} was returned to sender`);
    }
    await doc.ref.update(patch);

    // The second and last push: the card is on the carrier's truck (USPS
    // doesn't scan postcards at the door, so this is "delivered"). Transit
    // scans stay silent — they land the same day as "printing". A redelivered
    // webhook must not push twice.
    if (patch.status === STATUS.DELIVERED && row.status !== STATUS.DELIVERED) {
      this.notify(row.userId, {
        title: 'Your postcard was delivered',
        body: `Your card to ${row.recipient?.name || 'your recipient'} has arrived.`,
        data: { orderId: doc.id, status: STATUS.DELIVERED }
      });
    }
    return { handled: patch.status };
  },

  /**
   * Take the money for a card Lob has rendered. Idempotent: the capture
   * carries a fixed key and Stripe is asked first, so a redelivered webhook
   * or a reconcile pass after a lost response never double-charges. Never
   * throws — a failed capture leaves `capture_pending` for the reconciler.
   */
  async captureAfterRender(ref, row, reason) {
    const now = new Date().toISOString();
    try {
      const intent = await stripeClient.getPaymentIntent(row.stripePaymentIntentId);
      if (intent.status !== 'succeeded') {
        await stripeClient.capture(row.stripePaymentIntentId);
      }
      await ref.update({ capturedAt: now, awaitingRenderSince: null, error: null, lobLastEvent: reason, updatedAt: now });
      return true;
    } catch (error) {
      console.error(`[postcard-mail] capture after render failed for ${ref.id} (${reason}): ${error.message}`);
      await ref.update({ error: 'capture_pending', lobLastEvent: reason, updatedAt: now }).catch(() => {});
      return false;
    }
  },

  /**
   * The printer took the job and then refused it. Give the money back.
   *
   * This is the only path where a refund is the right answer rather than a
   * void: the capture already happened, so there is no hold left to release.
   * It costs us Stripe's fee, which is the correct trade — the alternative is
   * keeping someone's money for a postcard that will never be printed.
   */
  async unwindPrintFailure(doc, row, type) {
    const now = new Date().toISOString();
    if (row.status === STATUS.REFUNDED || row.status === STATUS.REJECTED) {
      return { handled: row.status }; // a repeated webhook must not refund twice
    }

    let status = STATUS.REJECTED;
    try {
      if (row.prepaid === true) {
        // A Fridge Mail card: the money was a pack credit or a subscription
        // slot, so give the credit back rather than touching Stripe.
        if (row.usesCredit) await require('./fridgeMailService').refundCredit(row.userId, `${type} on ${doc.id}`);
      } else if (row.capturedAt) {
        await stripeClient.refund(row.stripePaymentIntentId);
        status = STATUS.REFUNDED;
      } else {
        // Capture never landed, so the hold is still open and voiding is free.
        await stripeClient.voidAuthorization(row.stripePaymentIntentId);
      }
    } catch (error) {
      // Never leave the order looking fine. Flag it so a human settles up.
      console.error(`[postcard-mail] refund after ${type} failed for ${doc.id}: ${error.message}`);
      await doc.ref.update({
        status: STATUS.REJECTED, needsReview: true, lobLastEvent: type,
        error: `refund_failed: ${error.message}`.slice(0, 300), updatedAt: now
      });
      this.notify(row.userId, {
        title: "We couldn't print that postcard",
        body: `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed. We're sorting out your refund.`,
        data: { orderId: doc.id, status: STATUS.REJECTED }
      });
      return { handled: STATUS.REJECTED, refundFailed: true };
    }

    await doc.ref.update({ status, lobLastEvent: type, refundedAt: row.capturedAt ? now : null, updatedAt: now });
    if (row.prepaid === true) {
      this.notify(row.userId, {
        title: "We couldn't print this week's Fridge Mail card",
        body: `The card to ${row.recipient?.name || 'your recipient'} couldn't be printed.${row.usesCredit ? ' Your card credit was returned.' : ''} We'll try the next drawing on the next mailing day.`,
        data: { orderId: doc.id, status }
      });
      return { handled: status };
    }
    this.notify(row.userId, {
      title: "We couldn't print that postcard",
      body: row.capturedAt
        ? `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed, so we've refunded you.`
        : `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed, so you weren't charged.`,
      data: { orderId: doc.id, status }
    });
    console.error(`[postcard-mail] ${doc.id} ${type} — money returned (${status})`);
    return { handled: status };
  },
};
