// backend/services/appAttest/appAttestService.js
// App Attest for the requests that move points and coins (2026-11-01): the
// phone proves the request comes from the real FavCircles app on a real
// iPhone, not a script replaying the API.
//
// MONITOR ONLY: every protected request is checked and logged
// ("[app-attest] verified|missing|failed"), nothing is refused. Turning on
// refusals is an auth change Wes approves after the logs have soaked
// (APP_ATTEST_ENFORCE=true, full app builds only: the App Clip and older
// builds can't attest and are never refused).
//
// Challenges are stateless (Cloud Run has many instances): random bytes +
// expiry, HMAC-signed with a key derived from JWT_SECRET.
// Keys: appAttestKeys/{sha256(keyId)} = { keyId, publicKeyPem, environment,
//   counter, userId, createdAt, lastUsedAt }
//
// Request binding: the device signs clientData = "<METHOD> <path> <unix time>"
// (headers X-App-Attest-Key, X-App-Attest-Assertion, X-App-Attest-Time).

const crypto = require('crypto');
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const verifier = require('./appAttestVerifier');

const KEYS = 'appAttestKeys';
const APP_ID = '67E8B4E8HV.com.favcircles.circles';
const CHALLENGE_TTL_MS = 5 * 60 * 1000;
const CLOCK_SKEW_S = 10 * 60;

const enforcing = () => process.env.APP_ATTEST_ENFORCE === 'true';

const hmacKey = () => {
  if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET is not set');
  return crypto.createHash('sha256').update(`app-attest-challenge:${process.env.JWT_SECRET}`).digest();
};

/// base64url(random16 ‖ expiry ms ‖ hmac)
function issueChallenge(now = Date.now()) {
  const random = crypto.randomBytes(16);
  const expiry = Buffer.alloc(8);
  expiry.writeBigUInt64BE(BigInt(now + CHALLENGE_TTL_MS));
  const body = Buffer.concat([random, expiry]);
  const mac = crypto.createHmac('sha256', hmacKey()).update(body).digest();
  return Buffer.concat([body, mac]).toString('base64url');
}

function checkChallenge(challenge, now = Date.now()) {
  const raw = Buffer.from(String(challenge || ''), 'base64url');
  if (raw.length !== 56) return false;
  const body = raw.subarray(0, 24);
  const mac = crypto.createHmac('sha256', hmacKey()).update(body).digest();
  if (!crypto.timingSafeEqual(mac, raw.subarray(24))) return false;
  return Number(body.readBigUInt64BE(16)) >= now;
}

const keyDoc = (keyId) => getFirestore().collection(KEYS).doc(crypto.createHash('sha256').update(String(keyId)).digest('hex'));

/// A new key's attestation, once per install
async function registerKey({ userId, keyId, attestation, challenge }) {
  if (!keyId || !attestation) throw new ServiceError(400, 'ATTEST_MISSING', 'keyId and attestation are required');
  if (!checkChallenge(challenge)) throw new ServiceError(400, 'ATTEST_CHALLENGE', 'The challenge expired; ask for a new one');
  let result;
  try {
    result = verifier.verifyAttestation({ keyId, attestation: Buffer.from(attestation, 'base64'), challenge: Buffer.from(challenge), appId: APP_ID });
  } catch (error) {
    console.warn(`[app-attest] attestation rejected uid=${userId} reason=${error.reason || error.message}`);
    throw new ServiceError(400, 'ATTEST_INVALID', 'This device could not be verified');
  }
  const now = new Date().toISOString();
  await keyDoc(keyId).set({ keyId, publicKeyPem: result.publicKeyPem, environment: result.environment, counter: 0, userId, createdAt: now, lastUsedAt: now });
  console.info(`[app-attest] registered uid=${userId} env=${result.environment}`);
  return { environment: result.environment };
}

const clientDataFor = (method, path, time) => Buffer.from(`${String(method).toUpperCase()} ${path} ${time}`);

/// Checks one request's assertion. Never throws: { status, reason }
/// status: 'verified' | 'missing' | 'failed'
async function checkRequest({ method, path, headers, userId, now = Date.now() }) {
  const keyId = headers['x-app-attest-key'];
  const assertion = headers['x-app-attest-assertion'];
  const time = Number(headers['x-app-attest-time']);
  if (!keyId || !assertion) return { status: 'missing', reason: 'no headers' };
  if (!Number.isFinite(time) || Math.abs(now / 1000 - time) > CLOCK_SKEW_S) return { status: 'failed', reason: 'stale time' };
  try {
    const ref = keyDoc(keyId);
    return await getFirestore().runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) return { status: 'failed', reason: 'unknown key' };
      const key = doc.data();
      const counter = verifier.verifyAssertion({
        assertion: Buffer.from(String(assertion), 'base64'),
        clientData: clientDataFor(method, path, headers['x-app-attest-time']),
        publicKeyPem: key.publicKeyPem,
        previousCounter: key.counter || 0,
        appId: APP_ID
      });
      tx.update(ref, { counter, lastUsedAt: new Date(now).toISOString(), userId });
      return { status: 'verified', reason: key.environment };
    });
  } catch (error) {
    return { status: 'failed', reason: error.reason || error.message };
  }
}

/// The phone says it can attest (X-App-Attest-Capable: 1: a full app build
/// on hardware with App Attest). The clip, older builds and simulators don't
/// send it. An enforcement policy has to decide what an absent header means,
/// since a script can leave it off too; that's Wes's call after the soak.
const declaresAttest = (headers) => headers['x-app-attest-capable'] === '1';

module.exports = { KEYS, APP_ID, enforcing, issueChallenge, checkChallenge, registerKey, checkRequest, clientDataFor, declaresAttest };
