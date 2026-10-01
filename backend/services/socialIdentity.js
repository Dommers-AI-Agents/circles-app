// Which identity a social sign-in proves, and which email may find an
// existing account.
//
// Security audit 2026-10-01: sign-in used the email the CLIENT sent
// (`providedEmail || providerEmail`) to look up an existing account, and Apple
// tokens were decoded without checking their signature. Anyone who knew an
// email address could sign in as that person. The rules now:
//   - every provider token is verified against OUR app (Apple JWKS signature +
//     audience, Google `aud`, Facebook app id);
//   - only an email the provider itself vouches for may match an account;
//   - the email in the request body is never used for identity.
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const listFromEnv = (name) => (process.env[name] || '').split(',').map((s) => s.trim()).filter(Boolean);

/** Apple `aud` = the bundle id that asked: the app and the App Clip. */
const APPLE_AUDIENCES = ['com.favcircles.circles', 'com.favcircles.circles.Clip', ...listFromEnv('APPLE_AUDIENCES')];
/** Google `aud` = our OAuth client ids (iOS client from GoogleService-Info.plist). */
const GOOGLE_AUDIENCES = ['196924649787-rh9h60ndcfn6qes1tjde4ipo4tqlpko8.apps.googleusercontent.com', ...listFromEnv('GOOGLE_CLIENT_IDS')];
/** Facebook app id (Info.plist FacebookAppID). */
const FACEBOOK_APP_ID = process.env.FACEBOOK_APP_ID || '971348948407685';
const APPLE_ISSUER = 'https://appleid.apple.com';

const appleClient = jwksClient({ jwksUri: 'https://appleid.apple.com/auth/keys', cache: true, rateLimit: true });

function appleSigningKey(kid) {
  return new Promise((resolve, reject) => {
    appleClient.getSigningKey(kid, (err, key) => (err ? reject(err) : resolve(key.getPublicKey())));
  });
}

const isTrue = (v) => v === true || v === 'true';

/**
 * Verifies an Apple identity token's signature, issuer, audience and expiry.
 * `getKey` is injectable for tests. Returns { uid, email } where email is
 * only set when Apple marks it verified.
 */
async function verifyAppleToken(idToken, { getKey = appleSigningKey } = {}) {
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded || !decoded.header || !decoded.payload) throw new Error('Failed to decode token');
  if (decoded.payload.iss !== APPLE_ISSUER) throw new Error('Not an Apple ID token');
  if (!decoded.header.kid) throw new Error('Apple token has no key id');
  const key = await getKey(decoded.header.kid);
  const payload = jwt.verify(idToken, key, { algorithms: ['RS256'], issuer: APPLE_ISSUER, audience: APPLE_AUDIENCES });
  return {
    uid: payload.sub,
    // Apple always verifies the address it puts in the token (incl. Hide My Email relays)
    email: payload.email && isTrue(payload.email_verified ?? true) ? String(payload.email) : null,
    name: null,
    picture: null
  };
}

/** Google tokeninfo response → accepted only for our client ids; email only if verified. */
function acceptGoogleTokenInfo(tokenInfo) {
  if (!tokenInfo || !tokenInfo.sub || !GOOGLE_AUDIENCES.includes(tokenInfo.aud)) return null;
  return {
    uid: tokenInfo.sub,
    email: tokenInfo.email && isTrue(tokenInfo.email_verified) ? tokenInfo.email : null,
    name: tokenInfo.name,
    picture: tokenInfo.picture
  };
}

/** Firebase decoded ID token → email only when Firebase marks it verified. */
function firebaseVerifiedEmail(decodedToken) {
  return decodedToken && decodedToken.email && isTrue(decodedToken.email_verified) ? decodedToken.email : null;
}

/**
 * Facebook user access tokens are only accepted when they were issued to OUR
 * app (any app's token would otherwise work). `/app?access_token=` returns
 * the app the token belongs to — no app secret needed.
 */
async function facebookTokenIsOurs(accessToken, fetchImpl = fetch) {
  const res = await fetchImpl(`https://graph.facebook.com/app?access_token=${encodeURIComponent(accessToken)}`);
  if (!res.ok) return false;
  const app = await res.json();
  return String(app && app.id) === String(FACEBOOK_APP_ID);
}

module.exports = {
  APPLE_AUDIENCES, GOOGLE_AUDIENCES, FACEBOOK_APP_ID,
  verifyAppleToken, acceptGoogleTokenInfo, firebaseVerifiedEmail, facebookTokenIsOurs
};
