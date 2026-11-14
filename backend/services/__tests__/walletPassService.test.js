// Apple Wallet store cards (2026-11-01): pass.json, manifest, signature, zip
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const crypto = require('crypto');
const forge = require('node-forge');
const AdmZip = require('adm-zip');
const wallet = require('../wallet/walletPassService');

const venue = {
  venueId: 'v1', venueName: 'Sal’s Bakery', placeAddress: '1 Main St, Charlotte, NC',
  location: { lat: 35.2, lng: -80.8 }
};

// A throwaway signer + "WWDR" pair, the shape credentials() hands over
function testCredentials() {
  const keys = forge.pki.rsa.generateKeyPair(1024);
  const make = (cn) => {
    const cert = forge.pki.createCertificate();
    cert.publicKey = keys.publicKey;
    cert.serialNumber = '01';
    cert.validity.notBefore = new Date(Date.now() - 86_400_000);
    cert.validity.notAfter = new Date(Date.now() + 86_400_000);
    cert.setSubject([{ name: 'commonName', value: cn }]);
    cert.setIssuer([{ name: 'commonName', value: cn }]);
    cert.sign(keys.privateKey, forge.md.sha256.create());
    return cert;
  };
  return { cert: make('Pass Type ID: pass.com.favcircles.loyalty'), wwdr: make('Test WWDR'), key: keys.privateKey };
}

test('a live store shows points, the next reward in short fields, and the store on the lock screen', () => {
  const pass = wallet.passJson({
    serial: 's1', authToken: 't'.repeat(32), venue,
    progress: {
      live: true, points: 40, earnRate: 10, visits: 4, lastVisitAt: '2026-11-01T15:00:00Z',
      next: { title: 'Free coffee', pointsCost: 100, remaining: 60, canRedeem: false },
      nextRewardLine: '60 more points for a free coffee',
      offers: [{ title: 'Free coffee', pointsCost: 100 }, { title: 'Pastry', pointsCost: 30 }],
      announcement: { title: 'Live music', message: 'Friday 7 PM' }
    }
  });
  expect(pass).toMatchObject({
    formatVersion: 1, passTypeIdentifier: 'pass.com.favcircles.loyalty', teamIdentifier: '67E8B4E8HV',
    serialNumber: 's1', webServiceURL: 'https://api.favcircles.com/api/wallet', logoText: 'Sal’s Bakery'
  });
  expect(pass.storeCard.primaryFields[0]).toMatchObject({ key: 'points', value: 40 });
  expect(pass.storeCard.secondaryFields.map((f) => [f.label, f.value])).toEqual([['NEXT REWARD', 'Free coffee'], ['TO GO', '60 pts']]);
  expect(pass.storeCard.auxiliaryFields.map((f) => [f.label, f.value])).toEqual([['EACH PURCHASE', '+10 points'], ['PURCHASES', 4]]);
  // Wallet allows four front fields under the points on a store card
  expect(pass.storeCard.secondaryFields.length + pass.storeCard.auxiliaryFields.length).toBeLessThanOrEqual(4);
  const back = Object.fromEntries(pass.storeCard.backFields.map((f) => [f.key, f.value]));
  expect(back.menu).toBe('100 pts · Free coffee\n30 pts · Pastry  ✓');
  expect(back.news).toBe('Live music\nFriday 7 PM');
  expect(back.lastVisit).toBe('2026-11-01T15:00:00Z');
  expect(pass.locations[0]).toMatchObject({ latitude: 35.2, longitude: -80.8 });
});

test('a reward they can take now says so on the front', () => {
  const pass = wallet.passJson({
    serial: 's1', authToken: 't'.repeat(32), venue,
    progress: { live: true, points: 100, next: { title: 'Free coffee', pointsCost: 100, remaining: 0, canRedeem: true } }
  });
  expect(pass.storeCard.secondaryFields.map((f) => [f.label, f.value])).toEqual([['READY TO REDEEM', 'Free coffee'], ['IN THE APP', 'Tap Redeem']]);
});

test('the card opens the app on the store’s rewards (2026-11-02)', () => {
  const pass = wallet.passJson({ serial: 's1', authToken: 't'.repeat(32), venue: { ...venue, globalPlaceId: 'gp1' }, progress: { live: true, points: 0 } });
  expect(pass.associatedStoreIdentifiers).toEqual([6746807095]);
  expect(pass.appLaunchURL).toBe('circles://rewards/gp1');
  expect(pass.storeCard.backFields[0]).toMatchObject({ key: 'open', value: 'https://api.favcircles.com/app/rewards/gp1' });
  expect(pass.storeCard.backFields[0].attributedValue).toMatch(/<a href='https:\/\/api.favcircles.com\/app\/rewards\/gp1'>/);
});

test('a store without live rewards never says "earn" on the front', () => {
  const pass = wallet.passJson({ serial: 's1', authToken: 'x'.repeat(32), venue: { ...venue, location: null }, progress: { live: false, points: 0 } });
  expect(pass.storeCard.primaryFields[0]).toMatchObject({ label: 'SAVED STORE', value: 'Sal’s Bakery' });
  expect(pass.storeCard.secondaryFields).toEqual([]);
  expect(pass.storeCard.auxiliaryFields).toEqual([]);
  expect(pass.locations).toBeUndefined();
});

test('a claimed coupon rides on the back of the card, and leads the front when there is no points ladder (2026-11-14)', () => {
  const coupons = [{ title: '20% off any pickup order', onlineCode: 'TGOSTVQC', expiresAt: '2026-12-05T04:59:00.000Z' }];
  const live = wallet.passJson({
    serial: 's1', authToken: 't'.repeat(32), venue,
    progress: { live: true, points: 40, next: { title: 'Free coffee', pointsCost: 100, remaining: 60, canRedeem: false }, coupons }
  });
  expect(live.storeCard.secondaryFields[0].label).toBe('NEXT REWARD');
  expect(live.storeCard.backFields.find((f) => f.key === 'coupons')).toEqual({ key: 'coupons', label: 'Your coupon', value: '20% off any pickup order · code TGOSTVQC · through 2026-12-05' });

  const saved = wallet.passJson({ serial: 's1', authToken: 't'.repeat(32), venue, progress: { live: false, points: 0, coupons } });
  expect(saved.storeCard.secondaryFields).toEqual([{ key: 'coupon', label: 'YOUR COUPON', value: '20% off any pickup order' }]);
  const none = wallet.passJson({ serial: 's1', authToken: 't'.repeat(32), venue, progress: { live: false, points: 0, coupons: [] } });
  expect(none.storeCard.backFields.find((f) => f.key === 'coupons')).toBeUndefined();
});

test('the serial is stable per customer and store', () => {
  expect(wallet.serialFor('u1', 'v1')).toBe(wallet.serialFor('u1', 'v1'));
  expect(wallet.serialFor('u1', 'v1')).not.toBe(wallet.serialFor('u1', 'v2'));
});

test('the .pkpass holds every file, a matching manifest and a detached signature', () => {
  const creds = testCredentials();
  const pass = wallet.passJson({ serial: 's1', authToken: 'x'.repeat(32), venue, progress: { live: false, points: 0 } });
  const icon = Buffer.from('icon-bytes');
  const zip = new AdmZip(wallet.packagePass(pass, { 'icon.png': icon }, creds));
  const names = zip.getEntries().map((e) => e.entryName).sort();
  expect(names).toEqual(['icon.png', 'manifest.json', 'pass.json', 'signature']);

  const manifest = JSON.parse(zip.readAsText('manifest.json'));
  expect(manifest['icon.png']).toBe(crypto.createHash('sha1').update(icon).digest('hex'));
  expect(manifest['pass.json']).toBe(crypto.createHash('sha1').update(zip.readFile('pass.json')).digest('hex'));

  // Detached PKCS#7: no content inside, both certificates, one signer whose
  // messageDigest is the manifest's SHA-256
  const p7 = forge.pkcs7.messageFromAsn1(forge.asn1.fromDer(zip.readFile('signature').toString('binary')));
  expect(p7.certificates).toHaveLength(2);
  expect(p7.rawCapture.content).toBeUndefined();
  const digestAttr = p7.rawCapture.authenticatedAttributes
    .map((a) => forge.asn1.derToOid(a.value[0].value))
    .indexOf(forge.pki.oids.messageDigest);
  const digest = p7.rawCapture.authenticatedAttributes[digestAttr].value[1].value[0].value;
  expect(Buffer.from(digest, 'binary').toString('hex'))
    .toBe(crypto.createHash('sha256').update(zip.readFile('manifest.json')).digest('hex'));
});

test('without the certificate, nothing is built', async () => {
  delete process.env.PASS_CERT_P12_B64;
  delete process.env.PASS_CERT_PEM_B64;
  wallet._resetCredentials();
  expect(wallet.configured()).toBe(false);
  await expect(wallet.passForCustomer('u1', 'v1')).rejects.toMatchObject({ status: 503, code: 'WALLET_NOT_CONFIGURED' });
});
