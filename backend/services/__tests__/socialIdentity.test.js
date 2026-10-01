const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const social = require('../socialIdentity');

// A throwaway RSA key standing in for Apple's signing key.
const { privateKey, publicKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const otherKey = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey;
const getKey = async () => publicKey.export({ type: 'spki', format: 'pem' });

const appleToken = (claims = {}, { key = privateKey, kid = 'k1', alg = 'RS256' } = {}) => jwt.sign(
  { iss: 'https://appleid.apple.com', aud: 'com.favcircles.circles', sub: 'apple-sub-1', email: 'me@example.com', email_verified: 'true', ...claims },
  key, { algorithm: alg, keyid: kid, expiresIn: '10m' }
);

describe('Apple identity tokens (security audit 2026-10-01)', () => {
  test('a genuinely signed token for our app is accepted', async () => {
    const id = await social.verifyAppleToken(appleToken(), { getKey });
    expect(id).toMatchObject({ uid: 'apple-sub-1', email: 'me@example.com' });
  });

  test('the App Clip is an accepted audience too', async () => {
    await expect(social.verifyAppleToken(appleToken({ aud: 'com.favcircles.circles.Clip' }), { getKey })).resolves.toBeTruthy();
  });

  test('a self-made token (not signed by Apple) is rejected — the takeover', async () => {
    const forged = appleToken({ email: 'victim@example.com' }, { key: otherKey });
    await expect(social.verifyAppleToken(forged, { getKey })).rejects.toThrow();
  });

  test('an unsigned token is rejected', async () => {
    const header = Buffer.from(JSON.stringify({ alg: 'none', kid: 'k1' })).toString('base64url');
    const body = Buffer.from(JSON.stringify({ iss: 'https://appleid.apple.com', aud: 'com.favcircles.circles', sub: 'x', email: 'victim@example.com' })).toString('base64url');
    await expect(social.verifyAppleToken(`${header}.${body}.`, { getKey })).rejects.toThrow();
  });

  test('a token Apple issued to another app is rejected', async () => {
    await expect(social.verifyAppleToken(appleToken({ aud: 'com.someone.else' }), { getKey })).rejects.toThrow();
  });

  test('an expired token is rejected', async () => {
    const old = jwt.sign({ iss: 'https://appleid.apple.com', aud: 'com.favcircles.circles', sub: 's', exp: Math.floor(Date.now() / 1000) - 60 },
      privateKey, { algorithm: 'RS256', keyid: 'k1' });
    await expect(social.verifyAppleToken(old, { getKey })).rejects.toThrow();
  });

  test('an email Apple did not verify is not returned', async () => {
    const id = await social.verifyAppleToken(appleToken({ email_verified: 'false' }), { getKey });
    expect(id.email).toBeNull();
  });
});

describe('Google tokeninfo', () => {
  const ours = social.GOOGLE_AUDIENCES[0];
  test('accepted only for our client id, with a verified email', () => {
    expect(social.acceptGoogleTokenInfo({ aud: ours, sub: 'g1', email: 'a@b.com', email_verified: 'true' }))
      .toMatchObject({ uid: 'g1', email: 'a@b.com' });
    expect(social.acceptGoogleTokenInfo({ aud: 'another-app.apps.googleusercontent.com', sub: 'g1', email: 'a@b.com', email_verified: 'true' })).toBeNull();
    expect(social.acceptGoogleTokenInfo({ aud: ours, sub: 'g1', email: 'a@b.com', email_verified: 'false' }).email).toBeNull();
  });
});

describe('Firebase ID token email', () => {
  test('only a verified email counts', () => {
    expect(social.firebaseVerifiedEmail({ email: 'a@b.com', email_verified: true })).toBe('a@b.com');
    expect(social.firebaseVerifiedEmail({ email: 'victim@b.com', email_verified: false })).toBeNull();
    expect(social.firebaseVerifiedEmail({ email: 'victim@b.com' })).toBeNull();
  });
});

describe('Facebook tokens', () => {
  const fakeFetch = (appId) => async () => ({ ok: true, json: async () => ({ id: appId }) });
  test('accepted only when issued to our app', async () => {
    await expect(social.facebookTokenIsOurs('t', fakeFetch(social.FACEBOOK_APP_ID))).resolves.toBe(true);
    await expect(social.facebookTokenIsOurs('t', fakeFetch('123'))).resolves.toBe(false);
    await expect(social.facebookTokenIsOurs('t', async () => ({ ok: false }))).resolves.toBe(false);
  });
});
