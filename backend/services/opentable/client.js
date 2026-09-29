// backend/services/opentable/client.js
//
// OpenTable Partner API client for the link-out (Directory API, Bronze)
// partnership. OAuth 2.0 client credentials; the token lives ~48 h and is
// cached until shortly before it expires. OPENTABLE_ENV picks sandbox
// (pre-production) or production hosts; everything else is the same.
const { ServiceError } = require('../../utils/serviceError');

const HOSTS = {
  sandbox: { oauth: 'https://oauth-pp.opentable.com', platform: 'https://platform.otqa.com' },
  production: { oauth: 'https://oauth.opentable.com', platform: 'https://platform.opentable.com' }
};

const env = () => (process.env.OPENTABLE_ENV === 'production' ? 'production' : 'sandbox');
const hosts = () => HOSTS[env()];
const isConfigured = () => Boolean(process.env.OPENTABLE_CLIENT_ID && process.env.OPENTABLE_CLIENT_SECRET);

let cached = null; // { token, expiresAt, env }

const getToken = async () => {
  if (cached && cached.env === env() && Date.now() < cached.expiresAt) return cached.token;
  if (!isConfigured()) throw new ServiceError(503, 'OPENTABLE_NOT_CONFIGURED', 'OpenTable credentials are not set.');
  const basic = Buffer.from(`${process.env.OPENTABLE_CLIENT_ID}:${process.env.OPENTABLE_CLIENT_SECRET}`).toString('base64');
  const res = await fetch(`${hosts().oauth}/api/v2/oauth/token?grant_type=client_credentials`, {
    method: 'POST',
    headers: { Authorization: `Basic ${basic}`, 'Content-Length': '0' }
  });
  if (!res.ok) {
    throw new ServiceError(502, 'OPENTABLE_AUTH_FAILED', `OpenTable token request failed (${res.status}).`,
      { requestId: res.headers.get('ot-requestid') || null });
  }
  const body = await res.json();
  const ttlMs = Math.max(60, (body.expires_in || 3600) - 300) * 1000; // renew 5 min early
  cached = { token: body.access_token, expiresAt: Date.now() + ttlMs, env: env() };
  return cached.token;
};

/** One page of the restaurant directory. */
const fetchDirectoryPage = async ({ offset = 0, limit = 1000, country = null } = {}) => {
  const params = new URLSearchParams({ offset: String(offset), limit: String(limit) });
  if (country) params.set('country', country);
  const doFetch = async () => fetch(`${hosts().platform}/sync/directory?${params}`, {
    headers: { Authorization: `Bearer ${await getToken()}`, Accept: 'application/json', 'Accept-Encoding': 'gzip' }
  });
  let res = await doFetch();
  if (res.status === 401) { cached = null; res = await doFetch(); } // token revoked early
  if (!res.ok) {
    // OpenTable asks for the OT-RequestId on every issue report
    throw new ServiceError(502, 'OPENTABLE_DIRECTORY_FAILED', `OpenTable directory request failed (${res.status}).`,
      { requestId: res.headers.get('ot-requestid') || null, offset });
  }
  return res.json();
};

const _resetForTests = () => { cached = null; };

module.exports = { env, isConfigured, getToken, fetchDirectoryPage, _resetForTests };
