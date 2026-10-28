// A thin App Store Connect API client. The Team Key (ASC_KEY_ID / ASC_ISSUER_ID /
// ASC_PRIVATE_KEY_B64) signs a short-lived ES256 JWT per request batch.
// Only the calls the App Clip experience sync needs; nothing here is cached.
const jwt = require('jsonwebtoken');
const { ServiceError } = require('../../utils/serviceError');

const BASE = 'https://api.appstoreconnect.apple.com/v1';

function configured() {
  return !!(process.env.ASC_KEY_ID && process.env.ASC_ISSUER_ID && process.env.ASC_PRIVATE_KEY_B64);
}

let cachedToken = null;
function token() {
  if (!configured()) throw new ServiceError(503, 'ASC_NOT_CONFIGURED', 'App Store Connect API key is not configured');
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - now > 60) return cachedToken.value;
  const key = Buffer.from(process.env.ASC_PRIVATE_KEY_B64, 'base64').toString('utf8');
  const exp = now + 15 * 60;
  const value = jwt.sign({ iss: process.env.ASC_ISSUER_ID, iat: now, exp, aud: 'appstoreconnect-v1' },
    key, { algorithm: 'ES256', header: { kid: process.env.ASC_KEY_ID, typ: 'JWT' } });
  cachedToken = { value, exp };
  return value;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Apple's limiter answers 429 after a burst; the nightly sync and a manual
// publish both prefer waiting to failing. Three waits, a minute and up.
async function request(method, path, body, { raw = false, attempt = 0 } = {}) {
  const url = path.startsWith('http') ? path : `${BASE}${path}`;
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  if (res.status === 429 && attempt < 3) {
    const wait = 60000 * (attempt + 1);
    console.warn(`⏳ App Store Connect rate limit; waiting ${wait / 1000}s before retrying ${method} ${path}`);
    await sleep(wait);
    return request(method, path, body, { raw, attempt: attempt + 1 });
  }
  if (raw) return res;
  const text = await res.text();
  const json = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const detail = json && json.errors && json.errors[0];
    throw new ServiceError(res.status === 404 ? 404 : 502, 'ASC_ERROR',
      detail ? `${detail.title}: ${detail.detail}` : `App Store Connect ${res.status}`,
      json && json.errors);
  }
  return json;
}

// Uploads bytes to the pre-signed operations ASC hands back for an image.
async function uploadOperations(operations, buffer) {
  for (const op of operations) {
    const chunk = buffer.subarray(op.offset, op.offset + op.length);
    const headers = {};
    for (const h of op.requestHeaders || []) headers[h.name] = h.value;
    const res = await fetch(op.url, { method: op.method, headers, body: chunk });
    if (res.status === 409) {
      // Apple keeps one copy per image: the same bytes come back as the
      // id they already have, which the caller can use as is.
      const text = await res.text();
      const existing = text.match(/already exists with id\s*-?\s*([0-9a-f-]{36})/i);
      if (existing) return { existingId: existing[1] };
      throw new ServiceError(502, 'ASC_UPLOAD_FAILED', `Image upload part failed: 409 ${text.slice(0, 120)}`);
    }
    if (!res.ok) throw new ServiceError(502, 'ASC_UPLOAD_FAILED', `Image upload part failed: ${res.status}`);
  }
  return { uploaded: true };
}

const get = (path) => request('GET', path);
const post = (path, body) => request('POST', path, body);
const patch = (path, body) => request('PATCH', path, body);
const del = (path) => request('DELETE', path);

module.exports = { configured, get, post, patch, del, uploadOperations };
