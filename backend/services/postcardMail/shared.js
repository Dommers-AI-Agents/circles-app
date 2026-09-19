// backend/services/postcardMail/shared.js
// Constants, config and pure helpers shared by postcardMailService.js and its ./ mixins.
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
const { getFirestore, FieldValue } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const { sendInBackground } = require('../notifyQuiet');
const { escapeHtml } = require('../../utils/text');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const stripeClient = require('../stripeClient');
const lobClient = require('../lobClient');
const postcardShareService = require('../postcardShareService');
const notificationService = require('../notificationService');

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

class MailError extends ServiceError {}

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

module.exports = { AUTHORIZATION_LIFETIME_DAYS, CANCEL_WINDOW_MINUTES, COLLECTIONS, DEFAULT_PRICE_CENTS, FieldValue, MAX_LOB_ATTEMPTS, MESSAGE_MAX_CHARS, MailError, OPEN_STATUSES, ORDER_ID_RE, RENDER_GRACE_MINUTES, STATUS, SUBMITTING_STALE_MINUTES, US_STATES, buildBackHtml, escapeHtml, formatDate, getFirestore, isEnabled, lobClient, normalizeMessage, normalizeRecipient, notificationService, postcardShareService, priceCents, requireEnabled, returnAddress, sendInBackground, stripeClient };
