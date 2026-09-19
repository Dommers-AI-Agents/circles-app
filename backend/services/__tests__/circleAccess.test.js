// "May this viewer open this circle?" — the single copy of the tier check that
// the per-place endpoints share. Public costs no reads; Inner Circle costs two.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { canViewCircleFor, areConnected } = require('../circleAccess');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const connect = (a, b) => mockDb.rows(COLLECTIONS.CONNECTIONS).set(`${a}_${b}`, { userId: a, connectedUserId: b, status: 'accepted' });
const circle = (privacy, extra = {}) => ({ owner: 'owner', privacy, ...extra });

beforeEach(() => {
  mockDb.rows(COLLECTIONS.CONNECTIONS).clear();
  mockDb.rows(COLLECTIONS.USERS).clear();
  mockDb.rows(COLLECTIONS.USERS).set('owner', { innerCircle: ['inner'] });
  connect('friend', 'owner');   // accepted in one direction is enough
  connect('owner', 'inner');
});

test('nothing or nobody: false', async () => {
  expect(await canViewCircleFor(null, 'x')).toBe(false);
  expect(await canViewCircleFor(circle('public'), null)).toBe(false);
});

test('owner and guest list win at every tier, including private', async () => {
  expect(await canViewCircleFor(circle('private'), 'owner')).toBe(true);
  expect(await canViewCircleFor(circle('private', { sharedWith: ['guest'] }), 'guest')).toBe(true);
  expect(await canViewCircleFor(circle('private'), 'friend')).toBe(false);
});

test('public is open to any signed-in viewer without a read', async () => {
  const spy = jest.spyOn(mockDb, 'collection');
  expect(await canViewCircleFor(circle('public'), 'stranger')).toBe(true);
  expect(spy).not.toHaveBeenCalled();
  spy.mockRestore();
});

test('connections tier needs an accepted connection in either direction', async () => {
  expect(await canViewCircleFor(circle('myNetwork'), 'friend')).toBe(true);
  expect(await canViewCircleFor(circle('my_network'), 'friend')).toBe(true);
  expect(await canViewCircleFor(circle('myNetwork'), 'stranger')).toBe(false);
  mockDb.rows(COLLECTIONS.CONNECTIONS).set('pending', { userId: 'pend', connectedUserId: 'owner', status: 'pending' });
  expect(await canViewCircleFor(circle('myNetwork'), 'pend')).toBe(false);
});

test('inner circle needs connection AND a place on the owner\'s current list', async () => {
  expect(await canViewCircleFor(circle('innerCircle'), 'inner')).toBe(true);
  expect(await canViewCircleFor(circle('innerCircle'), 'friend')).toBe(false);
  mockDb.rows(COLLECTIONS.USERS).set('owner', { innerCircle: [] });
  expect(await canViewCircleFor(circle('innerCircle'), 'inner')).toBe(false);
});

test('unknown and follow-circle tiers stop cold', async () => {
  expect(await canViewCircleFor(circle('followCircle'), 'friend')).toBe(false);
  expect(await canViewCircleFor(circle('banana'), 'friend')).toBe(false);
});

test('areConnected is symmetric', async () => {
  expect(await areConnected('owner', 'friend')).toBe(true);
  expect(await areConnected('friend', 'owner')).toBe(true);
  expect(await areConnected('friend', 'inner')).toBe(false);
});
