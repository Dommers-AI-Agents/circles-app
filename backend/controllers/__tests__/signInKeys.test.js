// One plain key per person (Wes, 2026-10-09): new Apple/Google accounts get
// FavCircles' own id, a double-tapped first sign-in finds the account it
// just made, and a refreshed session carries the account's real key.
const jwt = require('jsonwebtoken');
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  admin: { firestore: { FieldPath: { documentId: () => '__name__' } } },
  getFirestore: () => mockDb,
  getAuth: () => ({ verifyIdToken: async () => { throw new Error('not a firebase token'); } }),
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/socialIdentity', () => ({
  verifyAppleToken: jest.fn(async () => ({ uid: '000454.abcdefabcdefabcdefabcdefabcdef12.1234', email: 'new@privaterelay.appleid.com' })),
  acceptGoogleTokenInfo: jest.fn(), firebaseVerifiedEmail: jest.fn(), facebookTokenIsOurs: jest.fn()
}));
jest.mock('../../services/onboardingService', () => ({ completeUserOnboarding: jest.fn(async () => ({})) }));
jest.mock('../../services/signupMonitor', () => ({ recordSignup: jest.fn() }));
jest.mock('../../services/emailService', () => ({ sendEmail: jest.fn(async () => {}), sendWelcomeEmail: jest.fn(async () => {}) }));
jest.mock('../../services/adminAlerts', () => ({ alertAdmin: jest.fn(async () => true) }));

process.env.JWT_SECRET = 'test-secret';
process.env.JWT_EXPIRE = '1h';
const controller = require('../firebaseAuthController');

const users = () => mockDb.collection('users');
const call = async (handler, body) => {
  let status = 200; let payload;
  const res = { status(s) { status = s; return this; }, json(p) { payload = p; return this; } };
  await handler({ body, ip: '127.0.0.1', headers: {} }, res, (e) => { throw e; });
  return { status, payload };
};
const allUsers = async () => (await users().limit(1000).get()).docs;

beforeEach(() => { mockDb.collections.clear(); });

test('a new Apple account is keyed by our own id, not Apple\'s', async () => {
  await call(controller.firebaseAuth, { idToken: 'apple-token', provider: 'apple' });
  const docs = await allUsers();
  expect(docs).toHaveLength(1);
  expect(docs[0].id).not.toContain('abcdef');
  expect(docs[0].id).not.toContain('.');
  expect(docs[0].data().linkedProviders.apple).toBe('000454.abcdefabcdefabcdefabcdefabcdef12.1234');
});

test('signing in again finds the same account', async () => {
  await call(controller.firebaseAuth, { idToken: 'apple-token', provider: 'apple' });
  await call(controller.firebaseAuth, { idToken: 'apple-token', provider: 'apple' });
  expect(await allUsers()).toHaveLength(1);
});

test('an existing account keyed by the trimmed Apple id still signs in', async () => {
  await users().doc('abcdefabcdefabcdefabcdefabcdef12').set({ email: 'old@example.com', displayName: 'Old' });
  await call(controller.firebaseAuth, { idToken: 'apple-token', provider: 'apple' });
  const docs = await allUsers();
  expect(docs.map((d) => d.id)).toEqual(['abcdefabcdefabcdefabcdefabcdef12']);
});

test('refresh re-signs with the account\'s own key', async () => {
  await users().doc('abcdefabcdefabcdefabcdefabcdef12').set({ email: 'old@example.com' });
  const old = jwt.sign({ uid: '000454.abcdefabcdefabcdefabcdefabcdef12.1234', email: 'old@example.com' }, 'test-secret');
  const { payload } = await call(controller.refreshToken, { refreshToken: old });
  expect(jwt.verify(payload.token, 'test-secret').uid).toBe('abcdefabcdefabcdefabcdefabcdef12');
});

test('refresh of a merged-away account answers as the survivor', async () => {
  await users().doc('ghost').set({ email: 'g@example.com', mergedInto: 'keeper' });
  await users().doc('keeper').set({ email: 'k@example.com' });
  const old = jwt.sign({ uid: 'ghost', email: 'g@example.com' }, 'test-secret');
  const { payload } = await call(controller.refreshToken, { refreshToken: old });
  expect(jwt.verify(payload.token, 'test-secret').uid).toBe('keeper');
});
