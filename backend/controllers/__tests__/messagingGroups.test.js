// Group conversations after the security audit of 2026-10-01: only the
// creator's connections, no emails in the response, bounded messages.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, getMessaging: () => ({}) }));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const { createNewConversation, sendMessage } = require('../messagingController');

const res = () => {
  const r = {};
  r.status = jest.fn((code) => { r.statusCode = code; return r; });
  r.json = jest.fn((body) => { r.body = body; return r; });
  return r;
};
const wes = { uid: 'wes', displayName: 'Wes' };

beforeEach(async () => {
  for (const name of [COLLECTIONS.USERS, COLLECTIONS.CONNECTIONS, COLLECTIONS.CONVERSATIONS]) mockDb.rows(name).clear();
  await mockDb.collection(COLLECTIONS.USERS).doc('britt').set({ displayName: 'Britt', email: 'britt@example.com', fcmTokens: ['t'] });
  await mockDb.collection(COLLECTIONS.USERS).doc('joe').set({ displayName: 'Joe', email: 'joe@example.com' });
  await mockDb.collection(COLLECTIONS.USERS).doc('stranger').set({ displayName: 'Stranger', email: 's@example.com' });
  await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c1').set({ userId: 'wes', connectedUserId: 'britt', status: 'accepted' });
  await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c2').set({ userId: 'joe', connectedUserId: 'wes', status: 'accepted' });
});

test('a group of connections is created, with public cards only', async () => {
  const out = res();
  await createNewConversation({ user: wes, body: { type: 'group', name: 'Trip', participants: ['britt', 'joe'] } }, out);
  expect(out.statusCode).toBe(201);
  const details = out.body.conversation.participantDetails;
  expect(details.map(d => d.displayName).sort()).toEqual(['Britt', 'Joe']);
  for (const d of details) {
    expect(d.email).toBeUndefined();
    expect(d.fcmTokens).toBeUndefined();
  }
});

test('a stranger in the participant list refuses the group', async () => {
  const out = res();
  await createNewConversation({ user: wes, body: { type: 'group', participants: ['britt', 'stranger'] } }, out);
  expect(out.statusCode).toBe(403);
  expect(out.body.code).toBe('not_connected');
  expect(mockDb.rows(COLLECTIONS.CONVERSATIONS).size).toBe(0);
});

test('a non-array participants body is a 400, not a 500', async () => {
  const out = res();
  await createNewConversation({ user: wes, body: { type: 'group', participants: 'britt' } }, out);
  expect(out.statusCode).toBe(400);
});

test('oversize messages are refused before anything is written', async () => {
  await mockDb.collection(COLLECTIONS.CONVERSATIONS).doc('g1').set({ type: 'group', participants: ['wes', 'britt'] });
  const out = res();
  await sendMessage({ user: wes, params: { conversationId: 'g1' }, body: { type: 'text', content: 'x'.repeat(4001) } }, out);
  expect(out.statusCode).toBe(400);
  expect(out.body.code).toBe('message_too_long');
});
