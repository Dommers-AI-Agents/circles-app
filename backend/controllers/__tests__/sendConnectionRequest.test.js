// POST /api/connections/invite after the security audit of 2026-10-01:
// a bare `autoAccept: true` no longer makes an accepted connection, invites
// the target really sent still connect in one tap, re-requests don't re-mail
// the target, blocks refuse, and the target's email never comes back.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
mockDb.batch = () => {
  const ops = [];
  return {
    update: (ref, data) => ops.push(() => ref.update(data)),
    set: (ref, data) => ops.push(() => ref.set(data)),
    delete: (ref) => ops.push(() => ref.delete()),
    commit: async () => { for (const op of ops) await op(); }
  };
};

const mockNotifyConnectionRequest = jest.fn(async () => {});
jest.mock('../../services/notificationService', () => ({
  notifyConnectionRequest: (...args) => mockNotifyConnectionRequest(...args),
  notifyConnectionAccepted: jest.fn(async () => {}),
  sendToUser: jest.fn(async () => {})
}));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));
jest.mock('../../services/activityService', () => ({}));
// Its placeCache starts an hourly setInterval that would keep Jest alive
jest.mock('../../services/userStatsCache', () => ({ getPlaceCountMap: jest.fn(async () => new Map()) }));
jest.mock('../../services/scoringService', () => ({}));
jest.mock('../../services/piggyBankService', () => ({ credit: jest.fn(async () => null) }));
jest.mock('../../services/funnelService', () => ({ stampFunnelMilestone: jest.fn() }));
jest.mock('../../services/emailService', () => ({ sendConnectionAcceptedEmail: jest.fn(async () => {}) }));

process.env.JWT_SECRET = 'test-secret';
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { signInviteToken, recordEmailInvite } = require('../../services/connectionRequestPolicy');
const { sendConnectionRequest } = require('../connectionController');

const res = () => {
  const r = {};
  r.status = jest.fn((code) => { r.statusCode = code; return r; });
  r.json = jest.fn((body) => { r.body = body; return r; });
  return r;
};

const sal = { uid: 'sal', firebaseDocId: 'sal', email: 'sal@example.com', displayName: 'Sal' };
const send = async (body, user = sal) => {
  const out = res();
  await sendConnectionRequest({ user, body, params: {} }, out);
  // Post-response work (follows, notifications) runs after res.json
  await new Promise((resolve) => setImmediate(resolve));
  return out;
};
const connections = () => [...mockDb.rows(COLLECTIONS.CONNECTIONS).values()];

beforeEach(async () => {
  for (const name of [COLLECTIONS.USERS, COLLECTIONS.CONNECTIONS, COLLECTIONS.NOTIFICATIONS,
    'connectionInvites', 'connectionRequestLog', 'dailyBudgets']) {
    mockDb.rows(name).clear();
  }
  mockNotifyConnectionRequest.mockClear();
  delete process.env.CONNECTION_REQUEST_DAILY_BUDGET;
  await mockDb.collection(COLLECTIONS.USERS).doc('sal').set({ displayName: 'Sal', email: 'sal@example.com', following: [] });
  await mockDb.collection(COLLECTIONS.USERS).doc('wes').set({ displayName: 'Wes', email: 'wes@favcircles.com', phoneNumber: '+15550100', following: [] });
});

test('a bare autoAccept from a stranger only creates a pending request', async () => {
  const out = await send({ targetUserId: 'wes', autoAccept: true });
  expect(out.statusCode).toBe(201);
  expect(out.body.data.status).toBe('pending');
  expect(connections()).toHaveLength(1);
  expect(connections()[0].status).toBe('pending');
  // The target is asked, not enrolled
  expect(mockNotifyConnectionRequest).toHaveBeenCalledWith('sal', 'wes', expect.any(String));
});

test('the response never carries the target\'s email or phone', async () => {
  const out = await send({ targetUserId: 'wes' });
  expect(out.body.data.connectedUser.displayName).toBe('Wes');
  expect(out.body.data.connectedUser.email).toBeUndefined();
  expect(out.body.data.connectedUser.phoneNumber).toBeUndefined();
});

test('a server-signed invite token from the target connects in one tap', async () => {
  const out = await send({ targetUserId: 'wes', autoAccept: true, inviteToken: signInviteToken('wes') });
  expect(out.statusCode).toBe(201);
  expect(out.body.data.status).toBe('accepted');
  expect(mockNotifyConnectionRequest).not.toHaveBeenCalled();
});

test('a token signed for someone else does not', async () => {
  const out = await send({ targetUserId: 'wes', autoAccept: true, inviteToken: signInviteToken('britt') });
  expect(out.body.data.status).toBe('pending');
});

test('an emailed invite from the target to the requester\'s address connects in one tap', async () => {
  await recordEmailInvite('wes', 'SAL@example.com');
  const out = await send({ targetUserId: 'wes', autoAccept: true });
  expect(out.body.data.status).toBe('accepted');
});

test('opening the link of someone who already asked you accepts their request', async () => {
  await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('req1').set({ userId: 'wes', connectedUserId: 'sal', status: 'pending' });
  const out = await send({ targetUserId: 'wes', autoAccept: true });
  expect(out.statusCode).toBe(200);
  expect(mockDb.rows(COLLECTIONS.CONNECTIONS).get('req1').status).toBe('accepted');
  expect(connections()).toHaveLength(1);
});

test('request → decline → request again does not re-notify within 24h', async () => {
  await send({ targetUserId: 'wes' });
  expect(mockNotifyConnectionRequest).toHaveBeenCalledTimes(1);
  // Target declines (the doc is deleted), requester asks again
  mockDb.rows(COLLECTIONS.CONNECTIONS).clear();
  const again = await send({ targetUserId: 'wes' });
  expect(again.statusCode).toBe(201);
  expect(connections()).toHaveLength(1);           // the request still exists
  expect(mockNotifyConnectionRequest).toHaveBeenCalledTimes(1); // but no new email/push
});

test('past the daily email budget, a new request is created but not emailed/pushed', async () => {
  process.env.EMAIL_DAILY_BUDGET = '0';
  try {
    const out = await send({ targetUserId: 'wes' });
    expect(out.statusCode).toBe(201);
    expect(mockNotifyConnectionRequest).not.toHaveBeenCalled();
  } finally {
    delete process.env.EMAIL_DAILY_BUDGET;
  }
});

test('a block in either direction refuses', async () => {
  await mockDb.collection(COLLECTIONS.USERS).doc('wes').set({ displayName: 'Wes', blockedUsers: ['sal'] });
  const out = await send({ targetUserId: 'wes' });
  expect(out.statusCode).toBe(403);
  expect(connections()).toHaveLength(0);
  const fromBlocker = await send({ targetUserId: 'wes' }, { ...sal, blockedBy: ['wes'] });
  expect(fromBlocker.statusCode).toBe(403);
});

test('new requests per day are capped', async () => {
  process.env.CONNECTION_REQUEST_DAILY_BUDGET = '1';
  await mockDb.collection(COLLECTIONS.USERS).doc('britt').set({ displayName: 'Britt' });
  expect((await send({ targetUserId: 'wes' })).statusCode).toBe(201);
  const out = await send({ targetUserId: 'britt' });
  expect(out.statusCode).toBe(429);
  expect(out.body.code).toBe('daily_limit');
});

test('an unknown user is a 404 without scanning the users collection', async () => {
  const users = mockDb.collection(COLLECTIONS.USERS);
  users.get = jest.fn(() => { throw new Error('full collection read'); });
  try {
    const out = await send({ targetUserId: 'nobody' });
    expect(out.statusCode).toBe(404);
    expect(users.get).not.toHaveBeenCalled();
  } finally {
    delete users.get;
  }
});
