// services/postcardMail/reconcile.js — methods of PostcardMailService (mixed into its prototype by the facade).
const { AUTHORIZATION_LIFETIME_DAYS, RENDER_GRACE_MINUTES, STATUS, SUBMITTING_STALE_MINUTES, isEnabled, lobClient, stripeClient } = require('./shared');

module.exports = {
  async reconcile() {
    const summary = { captured: 0, unstuck: 0, expired: 0, flagged: 0 };
    if (!isEnabled() || !stripeClient.isEnabled()) return { ...summary, disabled: true };
    const now = Date.now();

    // 0. Where every live card actually is, from Lob: a print refused after
    // capture becomes a refund, carrier scans move the status, a funding hold
    // on our account gets logged loudly. Webhooks do this faster when they
    // arrive; this is what holds when they don't.
    summary.tracking = await this.syncLiveOrders();

    // 1. At the printer but not paid. Normally rendered_pdf captures within
    // seconds; this is the net for a missed webhook. Ask Lob first — a card
    // it has failed must be voided, never captured — then capture only once
    // Lob has rendered it or the grace period has passed (a render failure
    // surfaces in seconds, so silence past the grace means it rendered).
    const unpaid = await this.col.where('status', '==', STATUS.SUBMITTED)
      .where('capturedAt', '==', null).limit(50).get();
    for (const doc of unpaid.docs) {
      const row = doc.data();
      // Fridge Mail cards are prepaid (packs/subscription): nothing to capture
      if (row.prepaid === true) continue;
      let lob = null;
      try {
        lob = row.lobPostcardId ? await lobClient.getPostcard(row.lobPostcardId) : null;
      } catch (error) {
        console.warn(`[postcard-mail] ${doc.id} Lob lookup failed during reconcile: ${error.message}`);
      }
      const lobStatus = lob && typeof lob.status === 'string' ? lob.status : null;
      if (lobStatus === 'failed' || lobStatus === 'rejected') {
        await this.unwindPrintFailure(doc, row, `postcard.${lobStatus}`);
        summary.voided = (summary.voided || 0) + 1;
        continue;
      }
      const rendered = !!(lob && Array.isArray(lob.thumbnails) && lob.thumbnails.length > 0);
      const waitedMinutes = (now - Date.parse(row.awaitingRenderSince || row.submittingAt || row.updatedAt || row.createdAt)) / 60000;
      if (!rendered && waitedMinutes < RENDER_GRACE_MINUTES) continue; // rendered_pdf may still arrive
      const captured = await this.captureAfterRender(doc.ref, row, rendered ? 'reconcile:rendered' : 'reconcile:grace');
      if (captured) {
        summary.captured++;
      } else {
        const ageHours = (now - Date.parse(row.updatedAt || row.createdAt)) / 3600000;
        if (ageHours > 24) {
          await doc.ref.update({ needsReview: true });
          console.error(`[postcard-mail] ${doc.id} mailed but never captured — needs review`);
          summary.flagged++;
        }
      }
    }

    // 2. A release tick died mid-flight. Ask Lob whether the card exists
    // (the order id is the idempotency key) before deciding.
    const staleIso = new Date(now - SUBMITTING_STALE_MINUTES * 60000).toISOString();
    const stuck = await this.col.where('status', '==', STATUS.SUBMITTING)
      .where('updatedAt', '<=', staleIso).limit(25).get();
    for (const doc of stuck.docs) {
      // Compare-and-set, not a plain update: a merely slow release tick may
      // have finished between the scan and this write, and forcing a printed,
      // captured order back to `authorized` would show the user a Cancel
      // button on a card already in the mail.
      //
      // Retrying is safe rather than double-mailing because both vendor calls
      // carry idempotency keys — Lob keyed on the order id, Stripe on the
      // payment intent — and 15 minutes stale plus an hourly sweep sits well
      // inside Lob's key window.
      const moved = await this.transition(doc.ref, STATUS.SUBMITTING, {
        status: STATUS.AUTHORIZED, updatedAt: new Date().toISOString()
      });
      if (moved) {
        summary.unstuck++;
        console.warn(`[postcard-mail] ${doc.id} was stuck submitting — returned to authorized`);
      }
    }

    // 3. Orders that never got a hold, and holds Stripe has since released.
    const abandonedIso = new Date(now - 24 * 3600000).toISOString();
    const abandoned = await this.col.where('status', '==', STATUS.CREATED)
      .where('createdAt', '<=', abandonedIso).limit(50).get();
    for (const doc of abandoned.docs) {
      const moved = await this.transition(doc.ref, STATUS.CREATED, {
        status: STATUS.EXPIRED, updatedAt: new Date().toISOString()
      });
      if (moved) summary.expired++;
    }

    const lapsedIso = new Date(now - AUTHORIZATION_LIFETIME_DAYS * 24 * 3600000).toISOString();
    const lapsed = await this.col.where('status', '==', STATUS.AUTHORIZED)
      .where('authorizedAt', '<=', lapsedIso).limit(25).get();
    for (const doc of lapsed.docs) {
      const moved = await this.transition(doc.ref, STATUS.AUTHORIZED, {
        status: STATUS.EXPIRED, error: 'authorization_lapsed', updatedAt: new Date().toISOString()
      });
      if (moved) summary.expired++;
    }

    return summary;
  },
};
