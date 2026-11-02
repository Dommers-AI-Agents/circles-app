// Following a private profile takes the owner's yes (Wes, 2026-11-02)
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('firebase-admin/firestore', () => ({ FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (userId, n) => mockPushes.push({ userId, type: n.type }) }));
jest.mock('../piggyBankService', () => ({ credit: jest.fn(async () => null) }));
jest.mock('../sseService', () => ({ notifyUser: jest.fn() }));

const requests = require('../followRequestService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const user = (id, extra = {}) => mockDb.collection(COLLECTIONS.USERS).doc(id).set({
  displayName: id, following: [], followers: [], followingCount: 0, followersCount: 0, ...extra
});
const data = async (id) => (await mockDb.collection(COLLECTIONS.USERS).doc(id).get()).data();

beforeEach(async () => {
  mockDb.rows(COLLECTIONS.USERS).clear();
  mockDb.rows(COLLECTIONS.FOLLOW_REQUESTS).clear();
  mockPushes.length = 0;
  await user('owner', { profilePrivate: true });
  await user('asker');
});

test('asking twice leaves one request and tells the owner once', async () => {
  expect(await requests.request('asker', 'owner', 'Asker')).toEqual({ requested: true, alreadyRequested: false });
  expect(await requests.request('asker', 'owner', 'Asker')).toEqual({ requested: true, alreadyRequested: true });
  expect(await requests.isPending('asker', 'owner')).toBe(true);
  expect(mockPushes).toEqual([{ userId: 'owner', type: 'follow_request' }]);
  const list = await requests.listIncoming('owner');
  expect(list.map((r) => r.requesterId)).toEqual(['asker']);
  expect(list[0].user.displayName).toBe('asker');
});

test('accepting makes the follow and tells the asker; a second accept does nothing', async () => {
  await requests.request('asker', 'owner', 'Asker');
  expect(await requests.accept('owner', 'asker')).toBe(true);
  expect((await data('asker')).following).toEqual(['owner']);
  expect((await data('asker')).followingCount).toBe(1);
  expect((await data('owner')).followers).toEqual(['asker']);
  expect((await data('owner')).followersCount).toBe(1);
  expect(await requests.isPending('asker', 'owner')).toBe(false);
  expect(mockPushes.map((p) => p.type)).toEqual(['follow_request', 'follow_request_accepted']);
  expect(await requests.accept('owner', 'asker')).toBe(false);
});

test('declining and cancelling leave no follow', async () => {
  await requests.request('asker', 'owner', 'Asker');
  await requests.decline('owner', 'asker');
  expect(await requests.isPending('asker', 'owner')).toBe(false);
  await expect(requests.decline('owner', 'asker')).rejects.toMatchObject({ status: 404 });
  await requests.request('asker', 'owner', 'Asker');
  await requests.cancel('asker', 'owner');
  expect(await requests.listIncoming('owner')).toEqual([]);
  expect((await data('asker')).following).toEqual([]);
});

test('going public lets everyone waiting in', async () => {
  await user('second');
  await requests.request('asker', 'owner', 'Asker');
  await requests.request('second', 'owner', 'Second');
  expect(await requests.acceptAll('owner')).toBe(2);
  expect((await data('owner')).followers.sort()).toEqual(['asker', 'second']);
});
