// backend/services/stripeClient.js
// Thin wrapper over the Stripe SDK. Exists so the order state machine can be
// tested without a network — jest.mock('./stripeClient') and nothing reaches
// Stripe — and so the key is read lazily rather than at require time, which
// would break every test run and any boot without payment config.
const Stripe = require('stripe');

let client = null;

function isEnabled() {
  return Boolean(process.env.STRIPE_SECRET_KEY);
}

function stripe() {
  if (!isEnabled()) throw new Error('STRIPE_SECRET_KEY is not configured');
  if (!client) client = Stripe(process.env.STRIPE_SECRET_KEY);
  return client;
}

/**
 * Creates an authorization, not a charge. `capture_method: 'manual'` is the
 * whole design: the money is held, the customer can cancel for free (voiding
 * a hold costs nothing, while refunding a capture keeps Stripe's fee), and we
 * capture only once the printer has accepted the job.
 *
 * `allow_redirects: 'never'` guarantees no redirect-based payment method can
 * be selected, which is what lets the app skip return-URL handling entirely.
 */
async function createAuthorization({ orderId, userId, amountCents, currency = 'usd', description }) {
  return stripe().paymentIntents.create({
    amount: amountCents,
    currency,
    capture_method: 'manual',
    automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
    description,
    metadata: { orderId, userId }
  }, { idempotencyKey: `postcard-order-${orderId}` });
}

async function getPaymentIntent(id) {
  return stripe().paymentIntents.retrieve(id);
}

/** Takes the held money. Only ever called after the printer accepted the job. */
async function capture(id) {
  return stripe().paymentIntents.capture(id, {}, { idempotencyKey: `postcard-capture-${id}` });
}

/** Releases the hold. Free — no fee is charged on an uncaptured intent. */
async function voidAuthorization(id) {
  return stripe().paymentIntents.cancel(id);
}

/** Manual support action only; the automatic paths all void instead. */
async function refund(paymentIntentId) {
  return stripe().refunds.create({ payment_intent: paymentIntentId });
}

// ---------------------------------------------------------------- Fridge Mail
// Prepaid packs are ordinary immediate-capture payments; subscriptions save
// the Apple Pay card to a Customer through a SetupIntent and bill monthly.

/** An immediate charge (card packs). Idempotent on the client's order id. */
async function createPayment({ orderId, userId, amountCents, currency = 'usd', description, kind }) {
  return stripe().paymentIntents.create({
    amount: amountCents,
    currency,
    automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
    description,
    metadata: { orderId, userId, kind }
  }, { idempotencyKey: `${kind}-${orderId}` });
}

/** One Stripe Customer per user; the id is stored on the plan. */
async function ensureCustomer({ existingId, userId, email, name }) {
  if (existingId) {
    try {
      const existing = await stripe().customers.retrieve(existingId);
      if (existing && !existing.deleted) return existing;
    } catch (error) {
      // fall through and mint a new one
    }
  }
  return stripe().customers.create({ email: email || undefined, name: name || undefined, metadata: { userId } });
}

/** Saves a card for off-session charges. Apple Pay presents this exactly like a payment. */
async function createSetupIntent({ customerId, userId, kind }) {
  return stripe().setupIntents.create({
    customer: customerId,
    usage: 'off_session',
    automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
    metadata: { userId, kind }
  });
}

async function getSetupIntent(id) {
  return stripe().setupIntents.retrieve(id);
}

/** Makes the saved card the customer's default for invoices. */
async function setDefaultPaymentMethod({ customerId, paymentMethodId }) {
  return stripe().customers.update(customerId, {
    invoice_settings: { default_payment_method: paymentMethodId }
  });
}

async function priceByLookupKey(lookupKey) {
  const prices = await stripe().prices.list({ lookup_keys: [lookupKey], active: true, limit: 1 });
  return prices.data[0] || null;
}

/**
 * Starts billing now. `error_if_incomplete` means a declined first charge
 * throws instead of leaving an "incomplete" subscription behind.
 */
async function createSubscription({ customerId, priceId, quantity, paymentMethodId, userId, kind }) {
  return stripe().subscriptions.create({
    customer: customerId,
    items: [{ price: priceId, quantity }],
    default_payment_method: paymentMethodId,
    payment_behavior: 'error_if_incomplete',
    metadata: { userId, kind },
    expand: ['latest_invoice']
  }, { idempotencyKey: `${kind}-sub-${userId}-${Date.now()}` });
}

async function getSubscription(id) {
  return stripe().subscriptions.retrieve(id);
}

/** Recipient count changed. No proration: the current period absorbs it. */
async function updateSubscriptionQuantity({ subscriptionId, quantity }) {
  const sub = await stripe().subscriptions.retrieve(subscriptionId);
  const item = sub.items && sub.items.data && sub.items.data[0];
  if (!item) throw new Error('subscription has no items');
  return stripe().subscriptions.update(subscriptionId, {
    items: [{ id: item.id, quantity }],
    proration_behavior: 'none'
  });
}

async function cancelSubscriptionAtPeriodEnd(subscriptionId) {
  return stripe().subscriptions.update(subscriptionId, { cancel_at_period_end: true });
}

async function resumeSubscription(subscriptionId) {
  return stripe().subscriptions.update(subscriptionId, { cancel_at_period_end: false });
}

/** Throws unless the raw body really came from Stripe. */
function constructEvent(rawBody, signature) {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) throw new Error('STRIPE_WEBHOOK_SECRET is not configured');
  return stripe().webhooks.constructEvent(rawBody, signature, secret);
}

module.exports = {
  isEnabled,
  createAuthorization,
  getPaymentIntent,
  capture,
  voidAuthorization,
  refund,
  constructEvent,
  createPayment,
  ensureCustomer,
  createSetupIntent,
  getSetupIntent,
  setDefaultPaymentMethod,
  priceByLookupKey,
  createSubscription,
  getSubscription,
  updateSubscriptionQuantity,
  cancelSubscriptionAtPeriodEnd,
  resumeSubscription,
  publishableKey: () => process.env.STRIPE_PUBLISHABLE_KEY || null
};
