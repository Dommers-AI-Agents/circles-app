// backend/services/appAttest/appAttestVerifier.js
// Apple App Attest, verified by hand per Apple's "Validating apps that
// connect to your server" (2026-11-01). Pure crypto: no Firestore here.
//
// Attestation (once per key): CBOR { fmt: 'apple-appattest', attStmt: { x5c, receipt }, authData }
//   1. x5c chains to Apple's App Attestation Root CA
//   2. nonce = SHA256(authData ‖ SHA256(challenge)) equals the credential
//      certificate's extension 1.2.840.113635.100.8.2
//   3. keyId = SHA256(the key's uncompressed EC point)
//   4. authData: rpIdHash = SHA256(appId), counter 0, aaguid dev/prod,
//      credentialId = keyId
// Assertion (every protected request): CBOR { signature, authenticatorData }
//   nonce = SHA256(authenticatorData ‖ SHA256(clientData)); the signature is
//   ECDSA-SHA256 over nonce with the attested key; rpIdHash matches; the
//   counter only goes up.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ROOT_PEM = fs.readFileSync(path.join(__dirname, '../../assets/appattest/Apple_App_Attestation_Root_CA.crt'), 'utf8');
const NONCE_OID = Buffer.from([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]); // 1.2.840.113635.100.8.2
const AAGUID = {
  production: Buffer.concat([Buffer.from('appattest'), Buffer.alloc(7)]),
  development: Buffer.from('appattestdevelop')
};

class AttestError extends Error {
  constructor(reason) { super(reason); this.reason = reason; }
}

const sha256 = (...parts) => crypto.createHash('sha256').update(Buffer.concat(parts.map((p) => Buffer.from(p)))).digest();

// --- a minimal CBOR reader: maps, arrays, byte/text strings, integers --------

function decodeCbor(buffer) {
  let offset = 0;
  const readLength = (info) => {
    if (info < 24) return info;
    if (info === 24) { const v = buffer.readUInt8(offset); offset += 1; return v; }
    if (info === 25) { const v = buffer.readUInt16BE(offset); offset += 2; return v; }
    if (info === 26) { const v = buffer.readUInt32BE(offset); offset += 4; return v; }
    if (info === 27) { const v = Number(buffer.readBigUInt64BE(offset)); offset += 8; return v; }
    throw new AttestError('cbor: indefinite lengths are not used by App Attest');
  };
  const item = () => {
    if (offset >= buffer.length) throw new AttestError('cbor: truncated');
    const byte = buffer.readUInt8(offset); offset += 1;
    const major = byte >> 5;
    const info = byte & 0x1f;
    switch (major) {
      case 0: return readLength(info);
      case 1: return -1 - readLength(info);
      case 2: { const n = readLength(info); const v = buffer.subarray(offset, offset + n); offset += n; return v; }
      case 3: { const n = readLength(info); const v = buffer.subarray(offset, offset + n).toString('utf8'); offset += n; return v; }
      case 4: { const n = readLength(info); const out = []; for (let i = 0; i < n; i += 1) out.push(item()); return out; }
      case 5: { const n = readLength(info); const out = {}; for (let i = 0; i < n; i += 1) { const k = item(); out[k] = item(); } return out; }
      default: throw new AttestError(`cbor: unsupported major type ${major}`);
    }
  };
  return item();
}

// --- DER: the nonce inside the credential certificate's extension ------------

/// One TLV at `offset`: { tag, start (of value), end }
function tlv(der, offset) {
  const tag = der[offset];
  let length = der[offset + 1];
  let start = offset + 2;
  if (length & 0x80) {
    const bytes = length & 0x7f;
    length = 0;
    for (let i = 0; i < bytes; i += 1) length = (length * 256) + der[start + i];
    start += bytes;
  }
  return { tag, start, end: start + length };
}

/// The 32-byte nonce: extension OID, then OCTET STRING { SEQUENCE { [1] { OCTET STRING nonce } } }
function certificateNonce(certDer) {
  const at = certDer.indexOf(NONCE_OID);
  if (at < 0) throw new AttestError('nonce extension missing');
  let node = tlv(certDer, at + NONCE_OID.length); // OCTET STRING (extnValue)
  if (node.tag === 0x01) node = tlv(certDer, node.end); // a `critical` BOOLEAN first
  if (node.tag !== 0x04) throw new AttestError('nonce extension malformed');
  const seq = tlv(certDer, node.start);
  const tagged = tlv(certDer, seq.start);
  const octets = tlv(certDer, tagged.start);
  if (seq.tag !== 0x30 || tagged.tag !== 0xa1 || octets.tag !== 0x04) throw new AttestError('nonce extension malformed');
  return certDer.subarray(octets.start, octets.end);
}

// --- authenticator data ------------------------------------------------------

function parseAuthData(authData) {
  if (authData.length < 37) throw new AttestError('authData too short');
  const parsed = {
    rpIdHash: authData.subarray(0, 32),
    flags: authData[32],
    counter: authData.readUInt32BE(33)
  };
  if (authData.length >= 55) {
    parsed.aaguid = authData.subarray(37, 53);
    const idLength = authData.readUInt16BE(53);
    parsed.credentialId = authData.subarray(55, 55 + idLength);
  }
  return parsed;
}

/// The EC public key as its 65-byte uncompressed point
const uncompressedPoint = (publicKey) => {
  const jwk = publicKey.export({ format: 'jwk' });
  return Buffer.concat([Buffer.from([0x04]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
};

/**
 * @param {object} p
 * @param {string} p.keyId base64 key identifier from the device
 * @param {Buffer} p.attestation the attestation object
 * @param {Buffer|string} p.challenge the server challenge the device hashed
 * @param {string} p.appId "<TeamID>.<bundle id>"
 * @param {Date} [p.now]
 * @returns {{ publicKeyPem: string, environment: 'production'|'development', receipt: Buffer }}
 */
function verifyAttestation({ keyId, attestation, challenge, appId, now = new Date(), rootPem = ROOT_PEM }) {
  const obj = decodeCbor(attestation);
  if (obj.fmt !== 'apple-appattest') throw new AttestError('wrong format');
  const x5c = obj.attStmt && obj.attStmt.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) throw new AttestError('certificate chain missing');
  const credCert = new crypto.X509Certificate(x5c[0]);
  const intermediate = new crypto.X509Certificate(x5c[1]);
  const root = new crypto.X509Certificate(rootPem);
  const valid = (c) => new Date(c.validFrom) <= now && now <= new Date(c.validTo);
  if (!intermediate.verify(root.publicKey) || !credCert.verify(intermediate.publicKey)) throw new AttestError('chain does not reach Apple');
  if (![credCert, intermediate, root].every(valid)) throw new AttestError('certificate expired');

  const authData = obj.authData;
  const nonce = sha256(authData, sha256(challenge));
  if (!certificateNonce(x5c[0]).equals(nonce)) throw new AttestError('nonce mismatch');

  const keyIdBytes = Buffer.from(keyId, 'base64');
  const point = uncompressedPoint(credCert.publicKey);
  if (!sha256(point).equals(keyIdBytes)) throw new AttestError('key id mismatch');

  const parsed = parseAuthData(authData);
  if (!parsed.rpIdHash.equals(sha256(appId))) throw new AttestError('app id mismatch');
  if (parsed.counter !== 0) throw new AttestError('counter not zero');
  let environment = null;
  if (parsed.aaguid && parsed.aaguid.equals(AAGUID.production)) environment = 'production';
  else if (parsed.aaguid && parsed.aaguid.equals(AAGUID.development)) environment = 'development';
  if (!environment) throw new AttestError('unknown environment');
  if (!parsed.credentialId || !parsed.credentialId.equals(keyIdBytes)) throw new AttestError('credential id mismatch');

  return {
    publicKeyPem: credCert.publicKey.export({ type: 'spki', format: 'pem' }),
    environment,
    receipt: obj.attStmt.receipt || null
  };
}

/**
 * @returns {number} the assertion's counter (store it; the next must be higher)
 */
function verifyAssertion({ assertion, clientData, publicKeyPem, previousCounter = 0, appId }) {
  const obj = decodeCbor(assertion);
  const authData = obj.authenticatorData;
  const signature = obj.signature;
  if (!Buffer.isBuffer(authData) || !Buffer.isBuffer(signature)) throw new AttestError('assertion malformed');
  const nonce = sha256(authData, sha256(clientData));
  const key = crypto.createPublicKey(publicKeyPem);
  if (!crypto.verify('sha256', nonce, key, signature)) throw new AttestError('bad signature');
  const parsed = parseAuthData(authData);
  if (!parsed.rpIdHash.equals(sha256(appId))) throw new AttestError('app id mismatch');
  if (parsed.counter <= previousCounter) throw new AttestError('counter replayed');
  return parsed.counter;
}

module.exports = { AttestError, decodeCbor, certificateNonce, parseAuthData, verifyAttestation, verifyAssertion, sha256 };
