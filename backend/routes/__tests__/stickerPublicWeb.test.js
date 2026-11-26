// The store's QR on a phone with no app (2026-11-26): anything that isn't an
// Apple device gets the store's web page; an iPhone keeps the App Clip / app
// page; STORE_WEB_PAGE=false and the generic JOINUS code keep the old page.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: {} }));
let mockVenue;
const mockStats = jest.fn();
jest.mock('../../services/rewardService', () => ({
  findVenueByCode: async () => mockVenue,
  incrementVenueStats: (...args) => mockStats(...args),
  effectiveEarnRate: () => 10,
  effectiveSavePoints: () => 25
}));
jest.mock('../../services/nfcStickerService', () => ({ recordTap: () => {}, pointsStickerTag: () => null }));
jest.mock('../../services/ownerSubscriptionService', () => ({
  isVenueLoyaltyActive: async () => true,
  registerScanEarns: async () => ({ earns: true })
}));
jest.mock('../../services/placePhotoService', () => ({ venueGallery: async () => ({ coverUrl: 'https://img/cover.jpg' }) }));
jest.mock('../../services/venueHelpers', () => ({
  activeOffers: (venue) => venue.offers || [],
  venueGlobalPlaceId: async () => 'gp1'
}));
const express = require('express');

const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';

let server;
let base;
beforeAll(async () => {
  const app = express();
  app.use('/s', require('../stickerPublicRoutes'));
  await new Promise((resolve) => { server = app.listen(0, resolve); });
  base = `http://127.0.0.1:${server.address().port}`;
});
afterAll(() => new Promise((resolve) => server.close(resolve)));
beforeEach(() => {
  delete process.env.STORE_WEB_PAGE;
  mockStats.mockClear();
  mockVenue = { venueId: 'v1', venueName: 'Demo Cafe', kind: 'window', windowCode: 'WIN123',
    offers: [{ offerId: 'o1', title: 'Free coffee', pointsCost: 50, active: true }] };
});
const get = async (path, ua) => {
  const res = await fetch(`${base}${path}`, { headers: { 'user-agent': ua } });
  return { status: res.status, text: await res.text(), cache: res.headers.get('cache-control') };
};

test('an Android phone gets the store page, and the scan is counted once', async () => {
  const res = await get('/s/win123', ANDROID);
  expect(res.status).toBe(200);
  expect(res.text).toContain('/public/store-page.js');
  expect(res.text).toContain('Save us. Get 25 points.');
  expect(res.text).not.toContain('Get the App');
  expect(res.cache).toBe('no-store');
  expect(mockStats).toHaveBeenCalledTimes(1);
  expect(mockStats).toHaveBeenCalledWith('v1', 'scans');
});

test('an iPhone keeps the page that opens the App Clip or the app', async () => {
  const res = await get('/s/WIN123', IPHONE);
  expect(res.text).toContain('content="circles://sticker?code=WIN123"');
  expect(res.text).not.toContain('store-page.js');
});

test('?web=1 shows the store page on any device, and is not counted as a scan', async () => {
  expect((await get('/s/WIN123?web=1', IPHONE)).text).toContain('store-page.js');
  expect(mockStats).not.toHaveBeenCalled();
});

test('the switch off, the generic code, and an unknown code keep the old page', async () => {
  process.env.STORE_WEB_PAGE = 'false';
  expect((await get('/s/WIN123', ANDROID)).text).toContain('Get the App');
  delete process.env.STORE_WEB_PAGE;
  mockVenue = { ...mockVenue, genericJoin: true };
  expect((await get('/s/JOINUS', ANDROID)).text).toContain('Get the App');
  mockVenue = null;
  expect((await get('/s/NOPE12', ANDROID)).text).toContain('Get the App');
});

// fetch won't send another Host header; node's http will
const getAs = (path, headers) => new Promise((resolve, reject) => {
  const { port } = server.address();
  require('http').get({ host: '127.0.0.1', port, path, headers }, (res) => {
    res.resume();
    res.on('end', () => resolve({ status: res.statusCode, location: res.headers.location }));
  }).on('error', reject);
});

test('on the QR host the store page moves to the web app host, so the sign-in is shared; uncounted there', async () => {
  const res = await getAs('/s/win123?c=ABCDEF', { 'user-agent': ANDROID, host: 'api.favcircles.com' });
  expect(res.status).toBe(302);
  expect(res.location).toBe('https://app.favcircles.com/s/WIN123?c=ABCDEF');
  expect(mockStats).not.toHaveBeenCalled();
  const iphone = await getAs('/s/WIN123', { 'user-agent': IPHONE, host: 'api.favcircles.com' });
  expect(iphone.status).toBe(200);
});
