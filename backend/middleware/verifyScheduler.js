// backend/middleware/verifyScheduler.js
//
// Authenticates the scheduled-task endpoints (/api/tasks/*).
//
// These endpoints send push notifications to the entire user base, email venue
// reports, rebuild suggestions, and spend money on LLM calls. They must never
// be triggerable by an anonymous caller.
//
// The previous check trusted `X-Cloudscheduler: true` and a `Google-Cloud-
// Scheduler` User-Agent. Both are request headers any client can set, so every
// task endpoint was effectively public. That check is gone — headers a caller
// controls can never be an authentication signal.
//
// Two accepted credentials, in order:
//
//   1. OIDC identity token (how Cloud Scheduler authenticates in production).
//      Google signs it per request, it expires in minutes, and it names the
//      service account that sent it. Verified against Google's public keys, the
//      expected audience, and — when SCHEDULER_SERVICE_ACCOUNT is set — the
//      exact caller identity. Nothing to leak or rotate.
//
//   2. A shared secret in SCHEDULER_SECRET (break-glass: manual runs, local
//      testing, and a fallback if OIDC is ever misconfigured). Compared in
//      constant time. Optional — leave it unset to accept OIDC only.
//
// Fails closed: with neither credential configured, every request is denied
// rather than silently falling back to "allow".

const crypto = require('crypto');
const { OAuth2Client } = require('google-auth-library');

const oauthClient = new OAuth2Client();

// Constant-time string comparison. A plain `===` leaks the secret one character
// at a time to an attacker who can measure response timing.
function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  // timingSafeEqual throws on length mismatch, which would itself be a leak —
  // hash first so both sides are always the same length.
  const hashA = crypto.createHash('sha256').update(bufA).digest();
  const hashB = crypto.createHash('sha256').update(bufB).digest();
  return crypto.timingSafeEqual(hashA, hashB);
}

function bearerToken(req) {
  const header = req.get('Authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : null;
}

async function verifyScheduler(req, res, next) {
  const token = bearerToken(req);

  if (!token) {
    console.warn(`🚫 [tasks] Unauthenticated request to ${req.originalUrl} from ${req.ip}`);
    return res.status(403).json({
      success: false,
      error: 'Forbidden - scheduled tasks require an authenticated caller'
    });
  }

  // 1. Break-glass shared secret.
  const secret = process.env.SCHEDULER_SECRET;
  if (secret && safeEqual(token, secret)) {
    return next();
  }

  // 2. Google-signed OIDC identity token from Cloud Scheduler.
  try {
    const audience = process.env.SCHEDULER_OIDC_AUDIENCE || undefined;
    const ticket = await oauthClient.verifyIdToken({ idToken: token, audience });
    const payload = ticket.getPayload() || {};
    const expectedAccount = process.env.SCHEDULER_SERVICE_ACCOUNT;

    const identityOk = !expectedAccount || payload.email === expectedAccount;
    if (payload.email_verified && identityOk) {
      return next();
    }

    console.warn(
      `🚫 [tasks] OIDC token rejected for ${req.originalUrl}: ` +
      `email=${payload.email || 'none'} verified=${payload.email_verified}`
    );
  } catch (error) {
    console.warn(`🚫 [tasks] OIDC verification failed for ${req.originalUrl}: ${error.message}`);
  }

  return res.status(403).json({
    success: false,
    error: 'Forbidden - scheduled tasks require an authenticated caller'
  });
}

module.exports = { verifyScheduler, safeEqual };
