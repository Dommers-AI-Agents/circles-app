// backend/config/secrets.js
//
// The signing secret, read in one place. Several modules used to fall back to
// a hard-coded string ('dev-secret', 'your-secret-key', '') when JWT_SECRET was
// missing — in production that would sign guest-order links, LinkedIn tokens
// and price quotes with a public value. Production refuses to boot without it;
// outside production a fixed development value keeps tests and local runs working.
const DEV_ONLY_SECRET = 'dev-secret';

const isProduction = () => process.env.NODE_ENV === 'production';

/** The JWT/HMAC secret. Throws in production when unset. */
function jwtSecret() {
  const value = process.env.JWT_SECRET;
  if (value) return value;
  if (isProduction()) throw new Error('JWT_SECRET is not set');
  return DEV_ONLY_SECRET;
}

/** Called once at server start: a production instance without the secret must not serve. */
function assertSecretsAtBoot() {
  if (isProduction() && !process.env.JWT_SECRET) {
    throw new Error('JWT_SECRET is required in production');
  }
}

module.exports = { jwtSecret, assertSecretsAtBoot };
