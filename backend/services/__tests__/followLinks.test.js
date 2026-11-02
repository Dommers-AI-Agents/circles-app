// Disconnect ends only the disconnecting person's follow (Wes, 2026-11-02)
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('firebase-admin/firestore', () => ({ FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));

const { removeFollow } = require('../followLinks');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const doc = (id) => mockDb.collection(COLLECTIONS.USERS).doc(id);

beforeEach(async () => {
  mockDb.rows(COLLECTIONS.USERS).clear();
  await doc('me').set({ following: ['them'], followers: ['them'], followingCount: 1, followersCount: 1 });
  await doc('them').set({ following: ['me'], followers: ['me'], followingCount: 1, followersCount: 1 });
});

test('I stop following them; they keep following me', async () => {
  await removeFollow('me', 'them');
  const me = (await doc('me').get()).data();
  const them = (await doc('them').get()).data();
  expect(me.following).toEqual([]);
  expect(me.followingCount).toBe(0);
  expect(me.followers).toEqual(['them']);
  expect(them.following).toEqual(['me']);
  expect(them.followers).toEqual([]);
  expect(them.followersCount).toBe(0);
});

test('nothing changes when I was not following', async () => {
  await removeFollow('me', 'them');
  await removeFollow('me', 'them');
  expect((await doc('them').get()).data().followersCount).toBe(0);
  expect((await doc('me').get()).data().followingCount).toBe(0);
});
