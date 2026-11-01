// The login screen's email step (2026-11-01): besides whether the account
// exists and has a passkey, which methods it signs in with, so a Google
// account isn't asked for a password it never had.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const { emailCheck } = require('../passkeyController');

const run = async (email) => {
  let body;
  await emailCheck({ body: { email } }, { json: (b) => { body = b; }, status: () => ({ json: (b) => { body = b; } }) });
  return body;
};

beforeEach(async () => {
  mockDb.rows('users').clear();
  await mockDb.collection('users').doc('g1').set({ email: 'brit@example.com', linkedProviders: { google: 'g1' } });
  await mockDb.collection('users').doc('m1').set({ email: 'pat@example.com', linkedProviders: { manual: true, passkey: true } });
});

test('a Google account says google and has no password', async () => {
  expect(await run('Brit@Example.com ')).toEqual({ success: true, exists: true, hasPasskey: false, methods: ['google'] });
});

test('a password account with a passkey says both', async () => {
  const out = await run('pat@example.com');
  expect(out.hasPasskey).toBe(true);
  expect(out.methods.sort()).toEqual(['passkey', 'password']);
});

test('an unknown email exists: false with no methods', async () => {
  expect(await run('nobody@example.com')).toEqual({ success: true, exists: false, hasPasskey: false, methods: [] });
});
