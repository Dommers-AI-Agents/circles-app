// backend/services/lobClient.js
// Thin wrapper over Lob's print-and-mail API (https://docs.lob.com). Plain
// fetch with basic auth — the SDK adds nothing we need. Mockable in jest so
// no test ever mails a postcard.
const crypto = require('crypto');

const BASE_URL = 'https://api.lob.com/v1';

/**
 * A Lob failure that knows whether retrying could ever help.
 *
 * This distinction decides what happens to a customer's money: a transient
 * failure leaves the authorization alone for the next tick, while a permanent
 * one voids the hold and tells them we couldn't print it. Getting it backwards
 * either spams Lob forever or cancels orders during a blip.
 */
class LobError extends Error {
  constructor(status, message, permanent) {
    super(message);
    this.status = status;
    this.permanent = permanent;
  }
}

function isEnabled() {
  return Boolean(process.env.LOB_API_KEY);
}

function authHeader() {
  const key = process.env.LOB_API_KEY;
  if (!key) throw new Error('LOB_API_KEY is not configured');
  return `Basic ${Buffer.from(`${key}:`).toString('base64')}`;
}

async function call(method, path, { body, idempotencyKey } = {}) {
  const headers = {
    Authorization: authHeader(),
    'Content-Type': 'application/json'
  };
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;

  let response;
  try {
    response = await fetch(`${BASE_URL}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined
    });
  } catch (error) {
    // Never reached Lob at all: always worth another tick.
    throw new LobError(0, `Lob unreachable: ${error.message}`, false);
  }

  const text = await response.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch (_) { /* non-JSON error body */ }

  if (!response.ok) {
    const message = json?.error?.message || text || `Lob request failed (${response.status})`;
    // 400/422 mean the request itself is wrong — a bad address or unusable
    // artwork — and will fail identically forever. Auth, rate limit and 5xx
    // are our problem or Lob's, and must not cancel a customer's order.
    const permanent = response.status === 400 || response.status === 422;
    throw new LobError(response.status, message, permanent);
  }
  return json;
}

/**
 * Checks a US address before anyone is asked to pay. Metered on some plans,
 * so call it once per completed address, not per keystroke.
 */
async function verifyUSAddress({ line1, line2, city, state, zip }) {
  const result = await call('POST', '/us_verifications', {
    body: {
      primary_line: line1,
      secondary_line: line2 || '',
      city,
      state,
      zip_code: zip
    }
  });
  const deliverability = result?.deliverability || 'undeliverable';
  return {
    deliverable: deliverability !== 'undeliverable',
    // Lob standardizes casing, street suffixes and ZIP+4. Showing the user
    // what will actually be printed avoids "that's not what I typed" later.
    standardized: {
      line1: result?.primary_line || line1,
      line2: result?.secondary_line || '',
      city: result?.components?.city || city,
      state: result?.components?.state || state,
      zip: result?.components?.zip_code || zip
    },
    deliverability
  };
}

/**
 * Prints and mails the card. `idempotencyKey` is the order id, so a retried
 * release tick can never produce a second postcard.
 */
async function createPostcard({ idempotencyKey, description, to, from, frontUrl, backHtml, mergeVariables }) {
  const result = await call('POST', '/postcards', {
    idempotencyKey,
    body: {
      description,
      to,
      from,
      front: frontUrl,
      back: backHtml,
      size: '4x6',
      mail_type: 'usps_first_class',
      use_type: 'operational',
      merge_variables: mergeVariables || undefined
    }
  });
  return {
    id: result.id,
    expectedDeliveryDate: result.expected_delivery_date || null,
    previewUrl: result.url || null,
    sendDate: result.send_date || null
  };
}

async function getPostcard(id) {
  return call('GET', `/postcards/${id}`);
}

/**
 * Verifies a Lob webhook: HMAC-SHA256 over "<timestamp>.<raw body>".
 * Rejects stale timestamps so a captured request can't be replayed.
 */
function verifyWebhook(rawBody, signature, timestamp, toleranceSeconds = 300) {
  const secret = process.env.LOB_WEBHOOK_SECRET;
  if (!secret) throw new Error('LOB_WEBHOOK_SECRET is not configured');
  if (!signature || !timestamp) return false;

  // Lob sends epoch milliseconds, but accept seconds too rather than reject
  // every webhook on a units mismatch: a 10-digit value can only be seconds
  // (13 digits is milliseconds for any date this century).
  const raw = Number(timestamp);
  if (!Number.isFinite(raw)) return false;
  const millis = String(Math.trunc(raw)).length <= 10 ? raw * 1000 : raw;
  if (Math.abs(Date.now() - millis) > toleranceSeconds * 1000) return false;

  const payload = `${timestamp}.${Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : rawBody}`;
  const expected = crypto.createHmac('sha256', secret).update(payload).digest('hex');
  const given = Buffer.from(String(signature), 'utf8');
  const mine = Buffer.from(expected, 'utf8');
  if (given.length !== mine.length) return false;
  return crypto.timingSafeEqual(given, mine);
}

module.exports = {
  LobError,
  isEnabled,
  verifyUSAddress,
  createPostcard,
  getPostcard,
  verifyWebhook,
  BASE_URL
};
