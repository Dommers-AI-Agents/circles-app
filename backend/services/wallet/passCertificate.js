// backend/services/wallet/passCertificate.js
// Where the Wallet pass certificate comes from, and its yearly renewal
// (2026-11-01). Apple's Pass Type ID certificates last about a year.
//
// Sources, newest-expiring wins:
//   - env: PASS_CERT_PEM_B64 + PASS_KEY_PEM_B64 (or PASS_CERT_P12_B64 +
//     PASS_CERT_PASSWORD), set at deploy
//   - Firestore systemSecrets/walletPassCert: written by the renewal job,
//     the key AES-256-GCM encrypted with a key derived from JWT_SECRET
//     (the collection is server-only: the rules deny every client)
// Instances re-read Firestore at most hourly, so a renewal reaches every
// instance within the hour with no redeploy.
//
// Renewal (task /api/tasks/wallet-cert-renew, monthly): when the live
// certificate has ≤45 days left, make a new RSA key + CSR, have App Store
// Connect issue a PASS_TYPE_ID certificate for the Pass Type ID
// (PASS_TYPE_PORTAL_ID, the portal's id for it), check the key matches, store it.
// The old certificate is left to expire; passes signed with it keep working.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const forge = require('node-forge');
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');

const SECRETS = 'systemSecrets';
const DOC = 'walletPassCert';
const RENEW_DAYS_BEFORE = 45;
const REFRESH_MS = 60 * 60 * 1000;
const WWDR_PEM = () => fs.readFileSync(path.join(__dirname, '../../assets/wallet/AppleWWDRCAG4.crt'), 'utf8');
const portalId = () => process.env.PASS_TYPE_PORTAL_ID || 'H54D9Y6S47';

// --- encryption of the stored key --------------------------------------------

const aesKey = () => {
  if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET is not set');
  return crypto.createHash('sha256').update(`wallet-pass-key:${process.env.JWT_SECRET}`).digest();
};

function encrypt(text) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', aesKey(), iv);
  const data = Buffer.concat([cipher.update(text, 'utf8'), cipher.final()]);
  return [iv, cipher.getAuthTag(), data].map((b) => b.toString('base64')).join('.');
}

function decrypt(blob) {
  const [iv, tag, data] = String(blob).split('.').map((s) => Buffer.from(s, 'base64'));
  const decipher = crypto.createDecipheriv('aes-256-gcm', aesKey(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
}

// --- the sources ---------------------------------------------------------------

const expiryOf = (certPem) => new Date(new crypto.X509Certificate(certPem).validTo);

/// { certPem, keyPem } from env, or null
function fromEnv() {
  if (process.env.PASS_CERT_PEM_B64 && process.env.PASS_KEY_PEM_B64) {
    return {
      certPem: Buffer.from(process.env.PASS_CERT_PEM_B64, 'base64').toString('utf8'),
      keyPem: Buffer.from(process.env.PASS_KEY_PEM_B64, 'base64').toString('utf8'),
      source: 'env'
    };
  }
  if (process.env.PASS_CERT_P12_B64) {
    const der = forge.util.decode64(process.env.PASS_CERT_P12_B64);
    const p12 = forge.pkcs12.pkcs12FromAsn1(forge.asn1.fromDer(der), process.env.PASS_CERT_PASSWORD || '');
    const certBag = (p12.getBags({ bagType: forge.pki.oids.certBag })[forge.pki.oids.certBag] || [])[0];
    const keyBag = (p12.getBags({ bagType: forge.pki.oids.pkcs8ShroudedKeyBag })[forge.pki.oids.pkcs8ShroudedKeyBag] || [])[0]
      || (p12.getBags({ bagType: forge.pki.oids.keyBag })[forge.pki.oids.keyBag] || [])[0];
    if (!certBag || !keyBag) throw new ServiceError(503, 'WALLET_NOT_CONFIGURED', 'The Wallet certificate is missing its key');
    return { certPem: forge.pki.certificateToPem(certBag.cert), keyPem: forge.pki.privateKeyToPem(keyBag.key), source: 'env' };
  }
  return null;
}

async function fromFirestore() {
  const doc = await getFirestore().collection(SECRETS).doc(DOC).get();
  if (!doc.exists || !doc.data().certPem || !doc.data().keyEnc) return null;
  return { certPem: doc.data().certPem, keyPem: decrypt(doc.data().keyEnc), source: 'renewed', certificateId: doc.data().certificateId };
}

/// The later-expiring of two candidates (null-safe)
const later = (a, b) => {
  if (!a) return b;
  if (!b) return a;
  return expiryOf(b.certPem) > expiryOf(a.certPem) ? b : a;
};

let cache = null; // { creds, at }

/// { cert, key, wwdr (forge), certPem, keyPem, expiresAt, source }
async function currentCredentials({ now = Date.now(), fresh = false } = {}) {
  if (cache && !fresh && now - cache.at < REFRESH_MS) return cache.creds;
  let stored = null;
  try {
    stored = await fromFirestore();
  } catch (error) {
    console.warn('⚠️ Wallet renewed certificate unreadable, using the deployed one:', error.message);
  }
  const chosen = later(fromEnv(), stored);
  if (!chosen) throw new ServiceError(503, 'WALLET_NOT_CONFIGURED', 'Apple Wallet cards are not set up yet');
  const creds = {
    cert: forge.pki.certificateFromPem(chosen.certPem),
    key: forge.pki.privateKeyFromPem(chosen.keyPem),
    wwdr: forge.pki.certificateFromPem(WWDR_PEM()),
    certPem: chosen.certPem,
    keyPem: chosen.keyPem,
    expiresAt: expiryOf(chosen.certPem).toISOString(),
    source: chosen.source
  };
  cache = { creds, at: now };
  return creds;
}

const configured = () => !!(process.env.PASS_CERT_P12_B64 || (process.env.PASS_CERT_PEM_B64 && process.env.PASS_KEY_PEM_B64));

// --- renewal -----------------------------------------------------------------

/// A new RSA key and its CSR (PEM)
function newKeyAndCsr() {
  const keys = forge.pki.rsa.generateKeyPair(2048);
  const csr = forge.pki.createCertificationRequest();
  csr.publicKey = keys.publicKey;
  csr.setSubject([{ name: 'commonName', value: 'FavCircles Pass' }]);
  csr.sign(keys.privateKey, forge.md.sha256.create());
  return { keyPem: forge.pki.privateKeyToPem(keys.privateKey), csrPem: forge.pki.certificationRequestToPem(csr) };
}

const samePublicKey = (certPem, keyPem) => {
  const fromCert = new crypto.X509Certificate(certPem).publicKey.export({ type: 'spki', format: 'der' });
  const fromKey = crypto.createPublicKey(keyPem).export({ type: 'spki', format: 'der' });
  return fromCert.equals(fromKey);
};

/**
 * Renews when the live certificate has ≤ RENEW_DAYS_BEFORE days left
 * (or `force`). `asc` = the App Store Connect client (injectable for tests).
 */
async function renewIfDue({ now = Date.now(), force = false, asc = require('../appStoreConnect/ascClient') } = {}) {
  const current = await currentCredentials({ now, fresh: true }).catch(() => null);
  const daysLeft = current ? Math.floor((new Date(current.expiresAt).getTime() - now) / 86_400_000) : null;
  if (!force && current && daysLeft > RENEW_DAYS_BEFORE) {
    return { renewed: false, daysLeft, expiresAt: current.expiresAt, source: current.source };
  }
  if (!asc.configured()) throw new Error('App Store Connect API key is not configured (ASC_*)');

  const { keyPem, csrPem } = newKeyAndCsr();
  const response = await asc.post('/certificates', {
    data: {
      type: 'certificates',
      attributes: { csrContent: csrPem, certificateType: 'PASS_TYPE_ID' },
      relationships: { passTypeId: { data: { type: 'passTypeIds', id: portalId() } } }
    }
  });
  const attributes = response.data.attributes;
  const certPem = new crypto.X509Certificate(Buffer.from(attributes.certificateContent, 'base64')).toString();
  if (!samePublicKey(certPem, keyPem)) throw new Error('Apple issued a certificate for a different key');

  const expiresAt = expiryOf(certPem).toISOString();
  await getFirestore().collection(SECRETS).doc(DOC).set({
    certPem,
    keyEnc: encrypt(keyPem),
    certificateId: response.data.id,
    expiresAt,
    renewedAt: new Date(now).toISOString(),
    previousExpiresAt: current ? current.expiresAt : null
  });
  cache = null;
  return { renewed: true, certificateId: response.data.id, expiresAt, previousExpiresAt: current ? current.expiresAt : null, daysLeftBefore: daysLeft };
}

module.exports = {
  RENEW_DAYS_BEFORE, configured, currentCredentials, renewIfDue,
  _internals: { encrypt, decrypt, newKeyAndCsr, samePublicKey, later, expiryOf },
  _resetCache: () => { cache = null; }
};
