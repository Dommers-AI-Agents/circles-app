// services/postcardMail/fulfilment.js — methods of PostcardMailService (mixed into its prototype by the facade).
const { FieldValue, MAX_LOB_ATTEMPTS, STATUS, buildBackHtml, isEnabled, lobClient, postcardShareService, returnAddress, sendInBackground, stripeClient } = require('./shared');

module.exports = {
  async releaseDue({ limit = 25 } = {}) {
    const summary = { released: 0, rejected: 0, retried: 0, skipped: 0 };
    if (!isEnabled() || !stripeClient.isEnabled() || !lobClient.isEnabled()) {
      return { ...summary, disabled: true };
    }
    const nowIso = new Date().toISOString();
    const snapshot = await this.col
      .where('status', '==', STATUS.AUTHORIZED)
      .where('cancelableUntil', '<=', nowIso)
      .limit(limit).get();

    for (const doc of snapshot.docs) {
      const outcome = await this.releaseOne(doc.id, doc.data());
      summary[outcome] = (summary[outcome] || 0) + 1;
    }
    return summary;
  },

  /**
   * One order, end to end: claim it, print it, then take the money. Returns
   * the summary key describing what happened.
   */
  async releaseOne(orderId, row) {
    const ref = this.col.doc(orderId);

    // Claim first. Until this succeeds someone else — or the user's cancel —
    // may still own this order.
    const claimed = await this.transition(ref, STATUS.AUTHORIZED, {
      status: STATUS.SUBMITTING,
      submittingAt: new Date().toISOString(),
      lobAttempts: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    if (!claimed) return 'skipped';

    try {
      const page = await this.ensurePublicPage(orderId, row);
      const from = returnAddress();
      const lob = await lobClient.createPostcard({
        idempotencyKey: orderId,
        description: `FavCircles postcard ${orderId}`,
        to: {
          name: row.recipient.name,
          address_line1: row.recipient.line1,
          address_line2: row.recipient.line2 || '',
          address_city: row.recipient.city,
          address_state: row.recipient.state,
          address_zip: row.recipient.zip,
          address_country: 'US'
        },
        // Omitted entirely when no return address is configured, which is the
        // norm. `from: null` is not the same as an absent `from` to Lob, so
        // the key must not be present at all — lobClient guards this too.
        ...(from ? { from } : {}),
        frontUrl: row.imageUrl,
        backHtml: buildBackHtml({
          message: row.message,
          senderName: page.senderName,
          pageUrl: page.url,
          qrUrl: page.qrUrl
        })
      });

      // Accepted. The money still waits: Lob renders asynchronously and a
      // render failure a few seconds from now must void the hold, not
      // refund a capture. `captureAfterRender` takes it on rendered_pdf.
      await ref.update({
        status: STATUS.SUBMITTED,
        lobPostcardId: lob.id,
        lobExpectedDeliveryDate: lob.expectedDeliveryDate,
        lobPreviewUrl: lob.previewUrl,
        publicPageToken: page.token,
        capturedAt: null,
        awaitingRenderSince: new Date().toISOString(),
        error: null,
        updatedAt: new Date().toISOString()
      });
      // Lob's expected date is its outer bound (production plus 5–7 business
      // days) and read as a promise of the slow date; the typical window is
      // the honest line (Wes, 2026-09-18).
      this.notify(row.userId, {
        title: 'Your postcard is printing',
        body: `On its way to ${row.recipient.name}. Typically arrives in 4 to 6 business days.`,
        data: { orderId, status: STATUS.SUBMITTED }
      });
      return 'released';
    } catch (error) {
      const permanent = error instanceof lobClient.LobError
        ? error.permanent
        : false;
      const attempts = (row.lobAttempts || 0) + 1;

      if (permanent || attempts >= MAX_LOB_ATTEMPTS) {
        await this.rejectOrder(orderId, row, error.message);
        return 'rejected';
      }
      // Transient: hand it back for the next tick, hold untouched.
      await ref.update({
        status: STATUS.AUTHORIZED,
        error: `lob_retry: ${error.message}`.slice(0, 300),
        updatedAt: new Date().toISOString()
      });
      console.error(`[postcard-mail] ${orderId} attempt ${attempts} failed, will retry: ${error.message}`);
      return 'retried';
    }
  },

  /**
   * We couldn't print it, so nobody pays. Voiding the hold is free, which is
   * the entire reason the money is held rather than captured up front.
   */
  async rejectOrder(orderId, row, reason) {
    try {
      await stripeClient.voidAuthorization(row.stripePaymentIntentId);
    } catch (error) {
      console.error(`[postcard-mail] void after rejection failed for ${orderId}: ${error.message}`);
    }
    await this.col.doc(orderId).update({
      status: STATUS.REJECTED,
      error: String(reason || 'rejected').slice(0, 300),
      rejectedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    // The one notification that must not be skipped: without it the sender
    // assumes their card is in the mail and only finds out when it never
    // arrives. Says plainly that no money was taken.
    this.notify(row.userId, {
      title: "We couldn't print that postcard",
      body: `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed, so you weren't charged.`,
      data: { orderId, status: STATUS.REJECTED }
    });
    console.error(`[postcard-mail] ${orderId} rejected (no charge): ${reason}`);
  },

  /**
   * Fire-and-forget push. An order's status is the record of truth; a failed
   * notification must never fail or retry the order it is describing.
   */
  notify(userId, { title, body, data }) {
    sendInBackground(userId, { type: 'postcard_order', title, body, data }, 'postcard-mail');
  },

  /**
   * The public page the printed QR points at. Minted here, on the server,
   * after the cancel window closed — never from a client-supplied token, so
   * a canceled order can't leave a page behind.
   */
  async ensurePublicPage(orderId, row) {
    if (row.publicPageToken) {
      const existing = await postcardShareService.get(row.publicPageToken);
      if (existing) {
        return {
          token: row.publicPageToken,
          url: `${postcardShareService.PUBLIC_BASE_URL}/postcard/${row.publicPageToken}`,
          qrUrl: `${postcardShareService.ASSET_BASE_URL}/postcard/${row.publicPageToken}/qr.png`,
          senderName: existing.senderName
        };
      }
    }
    const share = await postcardShareService.create({
      senderId: row.userId,
      imageUrl: row.imageUrl,
      message: row.message,
      templateId: row.templateId,
      placeRef: row.placeName ? { name: row.placeName, city: row.placeCity } : null
    });
    return {
      token: share.token,
      url: share.url,
      qrUrl: `${postcardShareService.ASSET_BASE_URL}/postcard/${share.token}/qr.png`,
      senderName: share.senderName
    };
  },
};
