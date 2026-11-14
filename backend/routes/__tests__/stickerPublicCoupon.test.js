// The sticker landing page (no app installed) names the flyer's coupon and
// carries it into the app link and the pasteboard hand-off (2026-11-14).
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: {} }));
const mockVenue = { venueId: 'v1', venueName: 'Vero Chicago Pizza', windowCode: 'WIN123', coupons: [
  { couponId: 'ABCDEF', title: '20% off any pickup order', expiresAt: '2099-01-01T00:00:00.000Z', active: true }
] };
jest.mock('../../services/rewardService', () => ({
  findVenueByCode: async () => mockVenue,
  incrementVenueStats: () => {},
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`
}));
jest.mock('../../services/nfcStickerService', () => ({ recordTap: () => {} }));
const express = require('express');

let server;
let base;
beforeAll(async () => {
  const app = express();
  app.use('/s', require('../stickerPublicRoutes'));
  await new Promise((resolve) => { server = app.listen(0, resolve); });
  base = `http://127.0.0.1:${server.address().port}`;
});
afterAll(() => new Promise((resolve) => server.close(resolve)));
const get = async (path) => {
  const res = await fetch(`${base}${path}`);
  return { status: res.status, text: await res.text() };
};

test('with ?c= the page says the coupon and keeps it on the app link and pasteboard', async () => {
  const res = await get('/s/WIN123?c=abcdef');
  expect(res.status).toBe(200);
  expect(res.text).toContain('Your coupon: 20% off any pickup order');
  expect(res.text).toContain('content="circles://sticker?code=WIN123&c=ABCDEF"');
  expect(res.text).toContain('data-clipboard="favcircles-sticker:WIN123;c=ABCDEF"');
});

test('without a coupon, or with one that has ended, the page is as before', async () => {
  const plain = await get('/s/WIN123');
  expect(plain.text).not.toContain('Your coupon');
  expect(plain.text).toContain('content="circles://sticker?code=WIN123"');
  expect(plain.text).toContain('data-clipboard="favcircles-sticker:WIN123"');
  mockVenue.coupons[0].expiresAt = '2020-01-01T00:00:00.000Z';
  const ended = await get('/s/WIN123?c=ABCDEF');
  expect(ended.text).not.toContain('Your coupon');
  expect(ended.text).toContain('content="circles://sticker?code=WIN123&c=ABCDEF"');
});
