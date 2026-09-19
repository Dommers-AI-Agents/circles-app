// backend/services/fridgeMail/shared.js
// Constants, config and pure helpers shared by fridgeMailService.js and its ./ mixins.
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
const { ServiceError } = require('../../utils/serviceError');
const { sendInBackground } = require('../notifyQuiet');
const { getFirestore, FieldValue } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const stripeClient = require('../stripeClient');
const lobClient = require('../lobClient');
const postcardMailService = require('../postcardMailService');
const postcardShareService = require('../postcardShareService');
const notificationService = require('../notificationService');

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

class FridgeMailError extends ServiceError {}

const isEnabled = () => process.env.POSTCARD_MAIL_ENABLED === '1';
const dryRun = () => process.env.FRIDGEMAIL_DRY_RUN === '1';
const { newId, nowIso } = require('../../utils/ids');
const { escapeHtml } = require('../../utils/text');
const { localClock } = require('../../utils/localClock');

function requireEnabled() {
  if (!isEnabled()) throw new FridgeMailError(503, 'mail_disabled', "Fridge Mail isn't available yet.");
  if (!stripeClient.isEnabled() || !lobClient.isEnabled()) {
    throw new FridgeMailError(503, 'mail_unconfigured', "Fridge Mail isn't available yet.");
  }
}

// Coerces numbers too: recipient fields sometimes arrive as numbers.
const clean = (value, max) => String(value || '').trim().slice(0, max);

function formatLongDate(now, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone: timeZone || 'America/New_York', month: 'long', day: 'numeric', year: 'numeric' }).format(now);
  } catch (error) {
    return new Intl.DateTimeFormat('en-US', { month: 'long', day: 'numeric', year: 'numeric' }).format(now);
  }
}

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

module.exports = { COLLECTIONS, FieldValue, FridgeMailError, KIND, MAX_QUEUE, MAX_RECIPIENTS, NAME_MAX, NOTE_MAX, ORDER_ID_RE, PACKS, PACK_KIND, RELATION_MAX, RESEND_AFTER_MS, SUBSCRIPTION_LOOKUP_KEY, SUBSCRIPTION_PRICE_CENTS, SUB_ACTIVE, buildFridgeBackHtml, clean, defaultPlan, dryRun, entitlement, escapeHtml, formatLongDate, getFirestore, isDue, isEnabled, lobClient, localClock, newId, notificationService, nowIso, postcardMailService, postcardShareService, requireEnabled, sendInBackground, stripeClient };
