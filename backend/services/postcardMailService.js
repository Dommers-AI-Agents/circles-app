// backend/services/postcardMailService.js
// Printed-and-mailed postcards: the order state machine.
//
// The money design in one paragraph. Stripe keeps its processing fee on a
// refund, so a cancel window backed by refunds costs real money every time
// someone uses it. Voiding an *uncaptured* authorization costs nothing. So
// Apple Pay places a hold, the cancel window runs against that hold, and the
// money is captured only once Lob has accepted the card for print. Every
// failure path therefore ends in a free void rather than a paid refund.
//
// Ordering matters too: submit to Lob BEFORE capturing. Lob is the step that
// can permanently refuse; capture on an already-authorized card almost never
// fails. In that order a refusal costs nobody anything.
//
// And "accepted" is not "printable": Lob takes the job over the API and
// renders it asynchronously a few seconds later, which is when a bad asset
// URL surfaces as `postcard.failed`. The first real order (2026-09-17) was
// captured on acceptance and failed on render — a paid refund for a card
// that never existed. So the capture now waits for Lob's `rendered_pdf`
// webhook; the hourly reconciler is the safety net when that webhook never
// arrives (it asks Lob directly and captures after a grace period).
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const stripeClient = require('./stripeClient');
const lobClient = require('./lobClient');
const postcardShareService = require('./postcardShareService');
const notificationService = require('./notificationService');

const STATUS = {
  CREATED: 'created',        // order written, hold not yet placed
  AUTHORIZED: 'authorized',  // hold in place, cancel window open
  CANCELED: 'canceled',      // user canceled, hold voided — free
  SUBMITTING: 'submitting',  // release job owns it; Lob call in flight
  SUBMITTED: 'submitted',    // Lob accepted; captured once Lob has rendered it
  IN_TRANSIT: 'in_transit',
  DELIVERED: 'delivered',
  RETURNED: 'returned_to_sender', // came back; a human decides what to do
  REJECTED: 'rejected',      // Lob permanently refused, hold voided — free
  EXPIRED: 'expired',        // never authorized, or the hold lapsed
  REFUNDED: 'refunded'       // manual support action only
};

// Statuses where the customer still has an open claim on their money.
const OPEN_STATUSES = [STATUS.CREATED, STATUS.AUTHORIZED, STATUS.SUBMITTING];

const DEFAULT_PRICE_CENTS = 399;
const CANCEL_WINDOW_MINUTES = 60;
const MESSAGE_MAX_CHARS = 350;   // what actually fits on a 4x6 back
const MAX_LOB_ATTEMPTS = 3;
const SUBMITTING_STALE_MINUTES = 15;
const AUTHORIZATION_LIFETIME_DAYS = 7; // Stripe voids uncaptured holds after this
// How long the reconciler waits for Lob's rendered_pdf webhook before it
// asks Lob directly and captures anyway (a render failure surfaces in seconds)
const RENDER_GRACE_MINUTES = 30;

const US_STATES = new Set(['AL','AK','AZ','AR','CA','CO','CT','DE','FL','GA','HI','ID','IL','IN','IA','KS','KY','LA','ME','MD','MA','MI','MN','MS','MO','MT','NE','NV','NH','NJ','NM','NY','NC','ND','OH','OK','OR','PA','RI','SC','SD','TN','TX','UT','VT','VA','WA','WV','WI','WY','DC','PR','VI','GU','AS','MP']);

const ORDER_ID_RE = /^[A-Za-z0-9_-]{8,64}$/;

class MailError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}

const isEnabled = () => process.env.POSTCARD_MAIL_ENABLED === '1';
const priceCents = () => Number(process.env.POSTCARD_PRICE_CENTS_US) || DEFAULT_PRICE_CENTS;

function requireEnabled() {
  if (!isEnabled()) throw new MailError(503, 'mail_disabled', 'Mailing printed postcards isn\'t available yet.');
  if (!stripeClient.isEnabled() || !lobClient.isEnabled()) {
    throw new MailError(503, 'mail_unconfigured', 'Mailing printed postcards isn\'t available yet.');
  }
}

/**
 * The return address, or null when we aren't printing one.
 *
 * Wes's decision (2026-09-14): no return address on printed postcards. Lob
 * accepts a postcard with no `from` for `use_type: "operational"`, verified
 * against their test API. The consequence is that USPS discards an
 * undeliverable card instead of returning it, so `postcard.returned_to_sender`
 * will never fire — the handler keeps that branch, but nothing depends on it.
 *
 * Kept configurable rather than deleted: setting all of POSTCARD_RETURN_ADDRESS_*
 * turns it back on with no code change. A partial address is ignored rather
 * than half-printed.
 */
function returnAddress() {
  const env = process.env;
  const required = {
    name: env.POSTCARD_RETURN_ADDRESS_NAME,
    address_line1: env.POSTCARD_RETURN_ADDRESS_LINE1,
    address_city: env.POSTCARD_RETURN_ADDRESS_CITY,
    address_state: env.POSTCARD_RETURN_ADDRESS_STATE,
    address_zip: env.POSTCARD_RETURN_ADDRESS_ZIP
  };
  if (Object.values(required).some((value) => !value)) return null;
  return {
    ...required,
    address_line2: env.POSTCARD_RETURN_ADDRESS_LINE2 || '',
    address_country: 'US'
  };
}

// ---------------------------------------------------------------- validation

function normalizeRecipient(input) {
  const r = input || {};
  const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
  const recipient = {
    name: str(r.name, 80),
    line1: str(r.line1, 120),
    line2: str(r.line2, 120),
    city: str(r.city, 60),
    state: str(r.state, 2).toUpperCase(),
    zip: str(r.zip, 10)
  };
  if (!recipient.name) throw new MailError(400, 'invalid_recipient', 'Who is this going to?');
  if (!recipient.line1) throw new MailError(400, 'invalid_recipient', 'A street address is required.');
  if (!recipient.city) throw new MailError(400, 'invalid_recipient', 'A city is required.');
  if (!US_STATES.has(recipient.state)) throw new MailError(400, 'invalid_recipient', 'A two-letter US state is required.');
  if (!/^\d{5}(-\d{4})?$/.test(recipient.zip)) throw new MailError(400, 'invalid_recipient', 'A 5-digit ZIP code is required.');
  return recipient;
}

function normalizeMessage(message) {
  const text = typeof message === 'string' ? message.trim() : '';
  if (text.length > MESSAGE_MAX_CHARS) {
    throw new MailError(400, 'message_too_long', `The back of a postcard fits ${MESSAGE_MAX_CHARS} characters.`);
  }
  return text;
}

/** "2026-09-20" -> "Sep 20", for a push that has to read at a glance. */
function formatDate(iso) {
  const d = new Date(`${iso}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
}

const escapeHtml = (s) => String(s || '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/**
 * The back of the card. Lob overlays the USPS address block in the
 * bottom-right, so that region stays empty: 3.2835in x 2.375in, 0.275in from
 * the right and 0.25in from the bottom. Everything else is ours.
 *
 * The QR is referenced by URL, not embedded as a data URI: Lob caps the HTML
 * at roughly 10k characters and an inline PNG blows straight past that.
 */
function buildBackHtml({ message, senderName, pageUrl, qrUrl }) {
  return `<html><head><meta charset="utf-8"><style>
  @page { size: 6.25in 4.25in; margin: 0; }
  body { width: 6.25in; height: 4.25in; margin: 0; font-family: Georgia, 'Times New Roman', serif; color: #1a202c; }
  .note { position: absolute; top: 0.375in; left: 0.375in; width: 2.6in; height: 3.1in; font-size: 11pt; line-height: 1.45; overflow: hidden; white-space: pre-wrap; }
  .from { position: absolute; top: 3.5in; left: 0.375in; width: 2.6in; font-size: 8pt; color: #4a5568; font-family: Helvetica, Arial, sans-serif; }
  .brand { position: absolute; top: 0.375in; right: 0.375in; width: 2.9in; text-align: right; font-size: 8pt; letter-spacing: .06em; text-transform: uppercase; color: #718096; font-family: Helvetica, Arial, sans-serif; }
  .qr { position: absolute; left: 0.375in; bottom: 0.3in; width: 0.72in; height: 0.72in; }
  .qrlabel { position: absolute; left: 1.2in; bottom: 0.52in; width: 1.6in; font-size: 7pt; color: #718096; font-family: Helvetica, Arial, sans-serif; }
</style></head><body>
  <div class="brand">Sent with FavCircles</div>
  <div class="note">${escapeHtml(message)}</div>
  <div class="from">— ${escapeHtml(senderName)}</div>
  <img class="qr" src="${escapeHtml(qrUrl)}" alt="">
  <div class="qrlabel">Scan to see this postcard online${pageUrl ? '' : ''}</div>
</body></html>`;
}

// ------------------------------------------------------------------- service

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
    const snapshot = await this.col.where('userId', '==', userId)
      .orderBy('createdAt', 'desc').limit(limit).get();
    return snapshot.docs.map((doc) => this.present(doc.id, doc.data()));
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
  }

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
  }

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
  }

  /**
   * Fire-and-forget push. An order's status is the record of truth; a failed
   * notification must never fail or retry the order it is describing.
   */
  notify(userId, { title, body, data }) {
    notificationService.sendToUser(userId, {
      type: 'postcard_order',
      title,
      body,
      data: { type: 'postcard_order', ...data }
    }).catch((error) => {
      console.error(`[postcard-mail] push failed for ${userId}: ${error.message}`);
    });
  }

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
  }

  /**
   * Hourly cleanup for everything the release job can't fix itself.
   */
  async reconcile() {
    const summary = { captured: 0, unstuck: 0, expired: 0, flagged: 0 };
    if (!isEnabled() || !stripeClient.isEnabled()) return { ...summary, disabled: true };
    const now = Date.now();

    // 1. At the printer but not paid. Normally rendered_pdf captures within
    // seconds; this is the net for a missed webhook. Ask Lob first — a card
    // it has failed must be voided, never captured — then capture only once
    // Lob has rendered it or the grace period has passed (a render failure
    // surfaces in seconds, so silence past the grace means it rendered).
    const unpaid = await this.col.where('status', '==', STATUS.SUBMITTED)
      .where('capturedAt', '==', null).limit(50).get();
    for (const doc of unpaid.docs) {
      const row = doc.data();
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
  }

  // ------------------------------------------------------------- webhooks

  /** Stripe's view of the truth, for when the client dies mid-flow. */
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
  }

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
  }

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
  }

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
      if (row.capturedAt) {
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
    this.notify(row.userId, {
      title: "We couldn't print that postcard",
      body: row.capturedAt
        ? `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed, so we've refunded you.`
        : `Your card to ${row.recipient?.name || 'your recipient'} couldn't be printed, so you weren't charged.`,
      data: { orderId: doc.id, status }
    });
    console.error(`[postcard-mail] ${doc.id} ${type} — money returned (${status})`);
    return { handled: status };
  }
}

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
