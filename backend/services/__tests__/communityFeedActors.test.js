// A sparse network still gets a feed (2026-11-01)
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const { addCommunityIfSparse, _reset } = require('../communityFeedActors');

beforeEach(async () => {
  _reset();
  mockDb.rows('users').clear();
  await mockDb.collection('users').doc('wes').set({ email: 'sgroiwes@gmail.com', placesCount: 900 });
  await mockDb.collection('users').doc('big').set({ email: 'a@b.com', placesCount: 300 });
  await mockDb.collection('users').doc('tester').set({ email: 'tester9@favcircles.com', placesCount: 999 });
  await mockDb.collection('users').doc('me').set({ email: 'me@x.com', placesCount: 1 });
});

test('a sparse network gets the founders and the most active mappers, never test accounts or me', async () => {
  const ids = new Set(['me']);
  const added = await addCommunityIfSparse(ids, { viewerId: 'me', networkSize: 0, db: mockDb });
  expect(added).toEqual(expect.arrayContaining(['wes', 'big']));
  expect(added).not.toContain('tester');
  expect(added).not.toContain('me');
});

test('a full network is left alone', async () => {
  const ids = new Set(['me', 'a', 'b', 'c', 'd', 'e']);
  expect(await addCommunityIfSparse(ids, { viewerId: 'me', networkSize: 5, db: mockDb })).toEqual([]);
  expect(ids.size).toBe(6);
});
