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
  publishableKey: () => process.env.STRIPE_PUBLISHABLE_KEY || null
};
