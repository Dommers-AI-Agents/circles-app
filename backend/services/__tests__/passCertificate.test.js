// Wallet pass certificate: sources and the yearly renewal (2026-11-01)
const mockStore = { doc: null };
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({
      doc: () => ({
        get: async () => ({ exists: !!mockStore.doc, data: () => mockStore.doc }),
        set: async (data) => { mockStore.doc = data; }
      })
    })
  })
}));
const crypto = require('crypto');
const forge = require('node-forge');
const passCertificate = require('../wallet/passCertificate');

const DAY = 86_400_000;

/// A self-signed cert for `keyPem` valid until `notAfter`
function certFor(keyPem, notAfter) {
  const key = forge.pki.privateKeyFromPem(keyPem);
  const cert = forge.pki.createCertificate();
  cert.publicKey = forge.pki.setRsaPublicKey(key.n, key.e);
  cert.serialNumber = '0' + crypto.randomBytes(4).toString('hex');
  cert.validity.notBefore = new Date(Date.now() - DAY);
  cert.validity.notAfter = notAfter;
  cert.setSubject([{ name: 'commonName', value: 'Pass Type ID: pass.com.favcircles.loyalty' }]);
  cert.setIssuer([{ name: 'commonName', value: 'Test' }]);
  cert.sign(key, forge.md.sha256.create());
  return forge.pki.certificateToPem(cert);
}

const smallKey = () => forge.pki.privateKeyToPem(forge.pki.rsa.generateKeyPair(1024).privateKey);

function deploy(certPem, keyPem) {
  process.env.PASS_CERT_PEM_B64 = Buffer.from(certPem).toString('base64');
  process.env.PASS_KEY_PEM_B64 = Buffer.from(keyPem).toString('base64');
}

/// A fake App Store Connect that signs whatever CSR it gets
const fakeAsc = (notAfter) => ({
  configured: () => true,
  post: jest.fn(async (pathName, body) => {
    const csr = forge.pki.certificationRequestFromPem(body.data.attributes.csrContent);
    const issuer = forge.pki.rsa.generateKeyPair(1024);
    const cert = forge.pki.createCertificate();
    cert.publicKey = csr.publicKey;
    cert.serialNumber = '01';
    cert.validity.notBefore = new Date(Date.now() - DAY);
    cert.validity.notAfter = notAfter;
    cert.setSubject(csr.subject.attributes);
    cert.setIssuer([{ name: 'commonName', value: 'Apple' }]);
    cert.sign(issuer.privateKey, forge.md.sha256.create());
    const der = forge.asn1.toDer(forge.pki.certificateToAsn1(cert)).getBytes();
    return { data: { id: 'NEWCERT1', attributes: { certificateContent: Buffer.from(der, 'binary').toString('base64') } } };
  })
});

beforeAll(() => { process.env.JWT_SECRET = 'test-secret'; });
beforeEach(() => { mockStore.doc = null; passCertificate._resetCache(); delete process.env.PASS_CERT_P12_B64; });

test('the stored key is encrypted and reads back', () => {
  const { encrypt, decrypt } = passCertificate._internals;
  const blob = encrypt('secret key');
  expect(blob).not.toContain('secret');
  expect(decrypt(blob)).toBe('secret key');
});

test('nothing to do while the certificate has more than 45 days', async () => {
  const key = smallKey();
  deploy(certFor(key, new Date(Date.now() + 200 * DAY)), key);
  const asc = fakeAsc(new Date(Date.now() + 365 * DAY));
  const result = await passCertificate.renewIfDue({ asc });
  expect(result.renewed).toBe(false);
  expect(result.daysLeft).toBeGreaterThan(190);
  expect(asc.post).not.toHaveBeenCalled();
});

test('within 45 days it renews through App Store Connect and the new one is used', async () => {
  const key = smallKey();
  deploy(certFor(key, new Date(Date.now() + 30 * DAY)), key);
  const asc = fakeAsc(new Date(Date.now() + 395 * DAY));
  const result = await passCertificate.renewIfDue({ asc });
  expect(result).toMatchObject({ renewed: true, certificateId: 'NEWCERT1' });
  const body = asc.post.mock.calls[0][1];
  expect(body.data.attributes.certificateType).toBe('PASS_TYPE_ID');
  expect(body.data.relationships.passTypeId.data).toEqual({ type: 'passTypeIds', id: 'H54D9Y6S47' });
  expect(mockStore.doc.keyEnc).toBeDefined();
  expect(mockStore.doc.certPem).toMatch(/BEGIN CERTIFICATE/);

  const creds = await passCertificate.currentCredentials({ fresh: true });
  expect(creds.source).toBe('renewed');
  expect(new Date(creds.expiresAt).getTime()).toBeGreaterThan(Date.now() + 390 * DAY);
  expect(passCertificate._internals.samePublicKey(creds.certPem, creds.keyPem)).toBe(true);
});

test('a newer deployed certificate wins over an older renewed one', async () => {
  const key = smallKey();
  deploy(certFor(key, new Date(Date.now() + 30 * DAY)), key);
  await passCertificate.renewIfDue({ asc: fakeAsc(new Date(Date.now() + 100 * DAY)) });
  const newerKey = smallKey();
  deploy(certFor(newerKey, new Date(Date.now() + 300 * DAY)), newerKey);
  const creds = await passCertificate.currentCredentials({ fresh: true });
  expect(creds.source).toBe('env');
});

test('a certificate for the wrong key is refused', async () => {
  const key = smallKey();
  deploy(certFor(key, new Date(Date.now() + 10 * DAY)), key);
  const asc = fakeAsc(new Date(Date.now() + 365 * DAY));
  asc.post.mockImplementationOnce(async () => {
    const other = certFor(smallKey(), new Date(Date.now() + 365 * DAY));
    return { data: { id: 'X', attributes: { certificateContent: Buffer.from(new crypto.X509Certificate(other).raw).toString('base64') } } };
  });
  await expect(passCertificate.renewIfDue({ asc })).rejects.toThrow('different key');
  expect(mockStore.doc).toBeNull();
});
