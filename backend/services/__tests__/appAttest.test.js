// App Attest (2026-11-01): challenges, attestation and assertion checks,
// against a throwaway CA built with openssl in the shape Apple uses.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const verifier = require('../appAttest/appAttestVerifier');
const service = require('../appAttest/appAttestService');

const APP_ID = '67E8B4E8HV.com.favcircles.circles';
const sha256 = (...parts) => verifier.sha256(...parts);

// A tiny CBOR writer for the shapes App Attest uses
function cbor(value) {
  const head = (major, n) => {
    if (n < 24) return Buffer.from([(major << 5) | n]);
    if (n < 256) return Buffer.from([(major << 5) | 24, n]);
    const b = Buffer.alloc(3); b[0] = (major << 5) | 25; b.writeUInt16BE(n, 1); return b;
  };
  if (Buffer.isBuffer(value)) return Buffer.concat([head(2, value.length), value]);
  if (typeof value === 'string') { const b = Buffer.from(value); return Buffer.concat([head(3, b.length), b]); }
  if (Array.isArray(value)) return Buffer.concat([head(4, value.length), ...value.map(cbor)]);
  const entries = Object.entries(value);
  return Buffer.concat([head(5, entries.length), ...entries.flatMap(([k, v]) => [cbor(k), cbor(v)])]);
}

const authData = ({ counter, aaguid, credentialId, appId = APP_ID }) => {
  const parts = [sha256(appId), Buffer.from([0x40]), Buffer.alloc(4)];
  parts[2].writeUInt32BE(counter);
  if (aaguid) {
    const len = Buffer.alloc(2); len.writeUInt16BE(credentialId.length);
    parts.push(aaguid, len, credentialId);
  }
  return Buffer.concat(parts);
};

const hasOpenssl = (() => { try { execFileSync('openssl', ['version']); return true; } catch { return false; } })();

/// root → intermediate → credential cert carrying the nonce extension
function makeChain(nonce) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'attest-'));
  const run = (...args) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
  for (const name of ['root', 'inter', 'cred']) run('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${name}.key`);
  run('req', '-x509', '-new', '-key', 'root.key', '-subj', '/CN=Test Root', '-days', '2', '-out', 'root.pem');
  fs.writeFileSync(path.join(dir, 'ca.ext'), 'basicConstraints=critical,CA:true\n');
  run('req', '-new', '-key', 'inter.key', '-subj', '/CN=Test Inter', '-out', 'inter.csr');
  run('x509', '-req', '-in', 'inter.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '2', '-extfile', 'ca.ext', '-out', 'inter.pem');
  // [1] { OCTET STRING nonce } inside a SEQUENCE, as Apple encodes it
  const inner = Buffer.concat([Buffer.from([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce]);
  fs.writeFileSync(path.join(dir, 'cred.ext'), `1.2.840.113635.100.8.2=DER:${inner.toString('hex')}\n`);
  run('req', '-new', '-key', 'cred.key', '-subj', '/CN=Test Cred', '-out', 'cred.csr');
  run('x509', '-req', '-in', 'cred.csr', '-CA', 'inter.pem', '-CAkey', 'inter.key', '-CAcreateserial', '-days', '2', '-extfile', 'cred.ext', '-out', 'cred.pem');
  const der = (f) => new crypto.X509Certificate(fs.readFileSync(path.join(dir, f))).raw;
  return {
    rootPem: fs.readFileSync(path.join(dir, 'root.pem'), 'utf8'),
    x5c: [der('cred.pem'), der('inter.pem')],
    credKey: crypto.createPrivateKey(fs.readFileSync(path.join(dir, 'cred.key'))),
    credPublic: new crypto.X509Certificate(fs.readFileSync(path.join(dir, 'cred.pem'))).publicKey
  };
}

const point = (publicKey) => {
  const jwk = publicKey.export({ format: 'jwk' });
  return Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
};

/// A full attestation for `challenge`, plus what a later assertion needs
function attest(challenge, { aaguid = Buffer.from('appattestdevelop') } = {}) {
  // The key id comes from the credential key, which the chain is built
  // around; build once to learn the key, again with the right nonce
  const probe = makeChain(Buffer.alloc(32));
  const keyIdBytes = sha256(point(probe.credPublic));
  const data = authData({ counter: 0, aaguid, credentialId: keyIdBytes });
  const nonce = sha256(data, sha256(challenge));
  // Re-sign a cred cert for the SAME key with the real nonce
  const chain = makeChainForKey(probe, nonce);
  return { chain, keyId: keyIdBytes.toString('base64'), attestation: cbor({ fmt: 'apple-appattest', attStmt: { x5c: chain.x5c, receipt: Buffer.from('r') }, authData: data }) };
}

function makeChainForKey(probe, nonce) {
  // Simplest: new chain whose credential key we then swap in via openssl
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'attest-'));
  const run = (...args) => execFileSync('openssl', args, { cwd: dir, stdio: 'pipe' });
  fs.writeFileSync(path.join(dir, 'cred.key'), probe.credKey.export({ type: 'sec1', format: 'pem' }));
  for (const name of ['root', 'inter']) run('ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', `${name}.key`);
  run('req', '-x509', '-new', '-key', 'root.key', '-subj', '/CN=Test Root', '-days', '2', '-out', 'root.pem');
  fs.writeFileSync(path.join(dir, 'ca.ext'), 'basicConstraints=critical,CA:true\n');
  run('req', '-new', '-key', 'inter.key', '-subj', '/CN=Test Inter', '-out', 'inter.csr');
  run('x509', '-req', '-in', 'inter.csr', '-CA', 'root.pem', '-CAkey', 'root.key', '-CAcreateserial', '-days', '2', '-extfile', 'ca.ext', '-out', 'inter.pem');
  const inner = Buffer.concat([Buffer.from([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce]);
  fs.writeFileSync(path.join(dir, 'cred.ext'), `1.2.840.113635.100.8.2=DER:${inner.toString('hex')}\n`);
  run('req', '-new', '-key', 'cred.key', '-subj', '/CN=Test Cred', '-out', 'cred.csr');
  run('x509', '-req', '-in', 'cred.csr', '-CA', 'inter.pem', '-CAkey', 'inter.key', '-CAcreateserial', '-days', '2', '-extfile', 'cred.ext', '-out', 'cred.pem');
  const der = (f) => new crypto.X509Certificate(fs.readFileSync(path.join(dir, f))).raw;
  return { rootPem: fs.readFileSync(path.join(dir, 'root.pem'), 'utf8'), x5c: [der('cred.pem'), der('inter.pem')], credKey: probe.credKey };
}

beforeAll(() => { process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret'; });

test('challenges are signed and expire', () => {
  const now = Date.now();
  const challenge = service.issueChallenge(now);
  expect(service.checkChallenge(challenge, now)).toBe(true);
  expect(service.checkChallenge(challenge, now + 6 * 60 * 1000)).toBe(false);
  const tampered = Buffer.from(challenge, 'base64url'); tampered[0] ^= 1;
  expect(service.checkChallenge(tampered.toString('base64url'), now)).toBe(false);
  expect(service.checkChallenge('nope', now)).toBe(false);
});

test('cbor reads maps, arrays, bytes, text and integers', () => {
  const out = verifier.decodeCbor(cbor({ a: [Buffer.from([1, 2]), 'x'], b: 'yz' }));
  expect(out.a[0]).toEqual(Buffer.from([1, 2]));
  expect(out.a[1]).toBe('x');
  expect(out.b).toBe('yz');
});

(hasOpenssl ? describe : describe.skip)('with a test CA', () => {
  const challenge = Buffer.from('server-challenge');

  test('a good attestation verifies and reports the environment', () => {
    const { chain, keyId, attestation } = attest(challenge);
    const result = verifier.verifyAttestation({ keyId, attestation, challenge, appId: APP_ID, rootPem: chain.rootPem });
    expect(result.environment).toBe('development');
    expect(result.publicKeyPem).toMatch(/BEGIN PUBLIC KEY/);
  });

  test('wrong challenge, wrong app, wrong root and wrong key id are refused', () => {
    const { chain, keyId, attestation } = attest(challenge);
    const base = { keyId, attestation, challenge, appId: APP_ID, rootPem: chain.rootPem };
    expect(() => verifier.verifyAttestation({ ...base, challenge: Buffer.from('other') })).toThrow('nonce mismatch');
    expect(() => verifier.verifyAttestation({ ...base, appId: 'X.other.app' })).toThrow('app id mismatch');
    expect(() => verifier.verifyAttestation({ ...base, rootPem: makeChain(Buffer.alloc(32)).rootPem })).toThrow('chain does not reach Apple');
    expect(() => verifier.verifyAttestation({ ...base, keyId: Buffer.alloc(32).toString('base64') })).toThrow('key id mismatch');
  });

  test('assertions verify with the attested key and the counter must climb', () => {
    const { chain, keyId, attestation } = attest(challenge);
    const { publicKeyPem } = verifier.verifyAttestation({ keyId, attestation, challenge, appId: APP_ID, rootPem: chain.rootPem });
    const clientData = service.clientDataFor('post', '/api/rewards/scan', '1730000000');
    const assertionFor = (counter, data = clientData) => {
      const auth = authData({ counter });
      const nonce = sha256(auth, sha256(data));
      return cbor({ signature: crypto.sign('sha256', nonce, chain.credKey), authenticatorData: auth });
    };
    expect(verifier.verifyAssertion({ assertion: assertionFor(1), clientData, publicKeyPem, previousCounter: 0, appId: APP_ID })).toBe(1);
    expect(() => verifier.verifyAssertion({ assertion: assertionFor(1), clientData, publicKeyPem, previousCounter: 1, appId: APP_ID })).toThrow('counter replayed');
    const otherRoute = service.clientDataFor('POST', '/api/piggy-bank/claim', '1730000000');
    expect(() => verifier.verifyAssertion({ assertion: assertionFor(2), clientData: otherRoute, publicKeyPem, previousCounter: 1, appId: APP_ID })).toThrow('bad signature');
  });
});

test('a request without headers is "missing", never an error', async () => {
  expect(await service.checkRequest({ method: 'POST', path: '/api/rewards/scan', headers: {} }))
    .toEqual({ status: 'missing', reason: 'no headers' });
  const stale = await service.checkRequest({ method: 'POST', path: '/x', headers: { 'x-app-attest-key': 'k', 'x-app-attest-assertion': 'a', 'x-app-attest-time': '1' } });
  expect(stale).toEqual({ status: 'failed', reason: 'stale time' });
});
