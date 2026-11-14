// The /q landing page (no Universal Link fired) opens the installed app on
// the code itself (circles://q/<code>) before offering the App Store; an
// expired or unknown code offers only the store (2026-11-14).
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({ collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) }), getMessaging: () => ({}), FieldValue: {}, admin: { firestore: { FieldValue: {} } } }));
const mockResolve = jest.fn();
jest.mock('../../services/scanActionService', () => ({
  resolve: (...a) => mockResolve(...a),
  urlFor: (code) => `https://api.favcircles.com/q/${code}`
}));
const express = require('express');

let server;
let base;
beforeAll(async () => {
  const app = express();
  app.use(require('../sharePageRoutes'));
  await new Promise((resolve) => { server = app.listen(0, resolve); });
  base = `http://127.0.0.1:${server.address().port}`;
});
afterAll(() => new Promise((resolve) => server.close(resolve)));
const get = async (path) => { const res = await fetch(`${base}${path}`); return { status: res.status, text: await res.text() }; };
const action = (extra = {}) => ({ code: 'AB7K2MQZ', kind: 'place', title: 'Sal’s', expired: false, creator: { displayName: 'Wes' }, places: [{ globalPlaceId: 'g1', name: 'Sal’s', photoUrl: null }], ...extra });

test('a live code: the page tries the app first, then the store', async () => {
  mockResolve.mockResolvedValueOnce(action());
  const res = await get('/q/AB7K2MQZ');
  expect(res.status).toBe(200);
  expect(res.text).toContain('<meta name="fc-app-link" content="circles://q/AB7K2MQZ">');
  expect(res.text).toContain('<meta name="fc-store-url" content="https://apps.apple.com/');
  expect(res.text).toContain('app-clip-bundle-id=com.favcircles.circles.Clip');
});

test('an expired or unknown code never bounces into the app', async () => {
  mockResolve.mockResolvedValueOnce(action({ expired: true }));
  expect((await get('/q/AB7K2MQZ')).text).not.toContain('fc-app-link');
  mockResolve.mockRejectedValueOnce(Object.assign(new Error('nope'), { status: 404 }));
  expect((await get('/q/ZZZZZZZZ')).text).not.toContain('fc-app-link');
});
