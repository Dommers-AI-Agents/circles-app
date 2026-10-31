// The owner's Activity tab shows their circles' CURRENT names and covers
// (Wes, 2026-10-31): a "Created circle Food" row reads "Charlotte Eats"
// after the rename; a deleted circle keeps the name it had.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const ownActivity = require('../ownActivity');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(async () => {
  for (const name of ['circles', 'activities']) mockDb.rows(name).clear();
  await put('circles', 'c1', { name: 'Charlotte Eats', coverImage: 'https://x/new.jpg', owner: 'u1' });
  await put('activities', 'a1', { type: 'circle_created', actorId: 'u1', targetType: 'circle', targetId: 'c1', targetName: 'Food',
    circleId: 'c1', circleName: 'Food', timestamp: '2026-10-20T10:00:00.000Z', metadata: { placePhoto: 'https://x/old.jpg' } });
  await put('activities', 'a2', { type: 'place_added', actorId: 'u1', targetType: 'place', targetId: 'p1', targetName: 'Optimist Hall',
    circleId: 'c1', circleName: 'Food', timestamp: '2026-10-21T10:00:00.000Z', metadata: { placePhoto: 'https://x/place.jpg' } });
  await put('activities', 'a3', { type: 'circle_created', actorId: 'u1', targetType: 'circle', targetId: 'gone', targetName: 'Trip',
    circleId: 'gone', circleName: 'Trip', timestamp: '2026-10-19T10:00:00.000Z', metadata: { placePhoto: null } });
});

test('circle rows show the current name and cover; place rows keep their photo', async () => {
  const { items } = await ownActivity.list({ userId: 'u1' });
  const byId = new Map(items.map((i) => [i.id, i]));
  expect(byId.get('a1')).toMatchObject({ targetName: 'Charlotte Eats', circleName: 'Charlotte Eats', thumbnailUrl: 'https://x/new.jpg' });
  expect(byId.get('a2')).toMatchObject({ targetName: 'Optimist Hall', circleName: 'Charlotte Eats', thumbnailUrl: 'https://x/place.jpg' });
  expect(byId.get('a3')).toMatchObject({ targetName: 'Trip', circleName: 'Trip' });
});
