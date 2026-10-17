// Locked "Connections only" circles on profiles (Wes, 2026-10-17): a viewer
// who isn't connected sees the owner's Connections circles greyed and locked
// (name, cover, place count, never places), so they ask to connect.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  admin: { firestore: { FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue } },
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/activityService', () => ({
  trackConnectionView: jest.fn(async () => {}),
  clearActivityNotification: jest.fn(async () => {})
}));

const { getUserCircles } = require('../circleSharingController');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const when = '2026-10-01T00:00:00.000Z';
const circle = (id, privacy, extra = {}) => put('circles', id, {
  name: id, owner: 'owner', privacy, category: 'food', coverImage: `https://x/${id}.jpg`,
  description: 'secret notes', sharedWith: [], createdAt: when, updatedAt: when, ...extra
});

beforeEach(async () => {
  for (const name of ['users', 'circles', 'places', 'connections']) mockDb.rows(name).clear();
  await put('users', 'owner', { displayName: 'Owner', following: [], innerCircle: ['friend'],
    circleOrder: ['open', 'lockedA', 'lockedB'] });
  await put('users', 'friend', { displayName: 'Friend', following: ['owner'] });
  await put('users', 'fan', { displayName: 'Fan', following: ['owner'] });
  await put('connections', 'c1', { userId: 'friend', connectedUserId: 'owner', status: 'accepted' });
  await circle('lockedB', 'myNetwork');
  await circle('open', 'public');
  await circle('lockedA', 'myNetwork');
  await circle('inner', 'innerCircle');
  await circle('hidden', 'private');
  await put('places', 'p1', { circleId: 'lockedA', addedBy: 'owner', name: 'Spot 1', createdAt: when });
  await put('places', 'p2', { circleId: 'lockedA', addedBy: 'owner', name: 'Spot 2', privacy: 'myNetwork', createdAt: when });
  await put('places', 'p3', { circleId: 'lockedA', addedBy: 'owner', name: 'Spot 3', privacy: 'private', createdAt: when });
  await put('places', 'p4', { circleId: 'lockedA', addedBy: 'owner', name: 'Spot 4', deletedAt: when, createdAt: when });
});

const load = async (viewer, query = {}, user = {}) => {
  const out = res();
  await getUserCircles({ params: { userId: 'owner' }, query, user: { uid: viewer, ...user } }, out);
  const body = out.json.mock.calls[0][0];
  expect(body.success).toBe(true);
  return body.data.circles;
};

test('a follower sees Connections circles locked, in the owner\'s order, with no places', async () => {
  const circles = await load('fan', { includeLocked: '1' });
  expect(circles.map(c => c._id)).toEqual(['open', 'lockedA', 'lockedB']);
  const a = circles.find(c => c._id === 'lockedA');
  expect(a).toMatchObject({ locked: true, name: 'lockedA', coverImage: 'https://x/lockedA.jpg',
    privacy: 'myNetwork', placesCount: 2, places: [], placesWithDetails: [] });
  expect(a).not.toHaveProperty('description');
  expect(a).not.toHaveProperty('sharedWith');
  expect(circles.find(c => c._id === 'open').locked).toBeUndefined();
});

test('Inner Circle and Private circles are never shown or counted', async () => {
  const ids = (await load('stranger', { includeLocked: '1' })).map(c => c._id);
  expect(ids).not.toContain('inner');
  expect(ids).not.toContain('hidden');
});

test('a connection gets the full circles, nothing locked', async () => {
  const circles = await load('friend', { includeLocked: '1' });
  expect(circles.some(c => c.locked)).toBe(false);
  expect(circles.find(c => c._id === 'lockedA').places.sort()).toEqual(['p1', 'p2']);
});

test('without includeLocked (older builds) the response is unchanged', async () => {
  expect((await load('fan')).map(c => c._id)).toEqual(['open']);
});

test('a block either way shows nothing locked', async () => {
  expect((await load('fan', { includeLocked: '1' }, { blockedUsers: ['owner'] })).map(c => c._id)).toEqual(['open']);
  await put('users', 'owner', { displayName: 'Owner', blockedUsers: ['fan'] });
  expect((await load('fan', { includeLocked: '1' })).map(c => c._id)).toEqual(['open']);
});
