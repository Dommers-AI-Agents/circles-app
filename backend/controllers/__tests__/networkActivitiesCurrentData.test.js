// The feed shows circles and people as they are NOW (Wes, 2026-10-31: "stored
// in the db and pulled from one place"): a renamed circle shows its new name
// and cover on old rows; a reaction shows the reactor's current name/photo.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  admin: { firestore: { FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue } },
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const { getNetworkActivities } = require('../activityController');
const { withCurrentCircle } = require('../../services/activityFeedOverlay');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const run = async () => {
  const r = res();
  const next = jest.fn();
  await getNetworkActivities({ user: { uid: 'viewer' }, query: {} }, r, next);
  expect(next).not.toHaveBeenCalled();
  return r.json.mock.calls[0][0];
};

beforeEach(async () => {
  for (const name of ['users', 'circles', 'activities', 'activityReactions', 'connections']) mockDb.rows(name).clear();
  await put('users', 'viewer', { displayName: 'Viewer', following: ['alex'] });
  await put('users', 'alex', { displayName: 'Alex', profilePicture: 'https://x/alex.jpg' });
  await put('users', 'rae', { displayName: 'Rae Now', profilePicture: 'https://x/rae-new.jpg' });
  // Renamed after the rows were written, with a new cover
  await put('circles', 'c1', { name: 'Charlotte Eats', coverImage: 'https://x/cover-new.jpg', owner: 'alex', privacy: 'public', sharedWith: [] });
  await put('activities', 'a1', {
    type: 'circle_created', actorId: 'alex', targetType: 'circle', targetId: 'c1', targetName: 'Food',
    circleId: 'c1', circleName: 'Food', timestamp: '2026-10-20T10:00:00.000Z',
    metadata: { placePhoto: 'https://x/cover-old.jpg' }
  });
  await put('activities', 'a2', {
    type: 'place_added', actorId: 'alex', targetType: 'place', targetId: 'p1', targetName: 'Optimist Hall',
    circleId: 'c1', circleName: 'Food', timestamp: '2026-10-21T10:00:00.000Z',
    metadata: { placePhoto: 'https://x/place.jpg', placePrivacy: 'public' }
  });
  await put('activityReactions', 'r1', { activityId: 'a1', userId: 'rae', emoji: '🔥', userName: 'Rae Then', userPhoto: 'https://x/rae-old.jpg' });
  await put('activityReactions', 'r2', { activityId: 'a1', userId: 'gone', emoji: '🔥', userName: 'Deleted Person', userPhoto: null });
});

test('feed rows show the circle\'s current name and cover after a rename', async () => {
  const body = await run();
  const byId = new Map(body.activities.map((a) => [a.id || a._id, a]));
  expect(byId.get('a1')).toMatchObject({ circleName: 'Charlotte Eats', targetName: 'Charlotte Eats' });
  expect(byId.get('a1').metadata.placePhoto).toBe('https://x/cover-new.jpg');
  // A place row: the circle's name is current, the photo stays the place's
  expect(byId.get('a2')).toMatchObject({ circleName: 'Charlotte Eats', targetName: 'Optimist Hall' });
  expect(byId.get('a2').metadata.placePhoto).toBe('https://x/place.jpg');
  expect(byId.get('a1').actor).toMatchObject({ displayName: 'Alex' });
});

test('reactions show the reacting person\'s current name and photo (stored only for a gone account)', async () => {
  const body = await run();
  const row = body.activities.find((a) => (a.id || a._id) === 'a1');
  const users = row.reactionSummary[0].users;
  expect(users).toEqual(expect.arrayContaining([
    { id: 'rae', displayName: 'Rae Now', profilePicture: 'https://x/rae-new.jpg' },
    { id: 'gone', displayName: 'Deleted Person', profilePicture: null }
  ]));
});

test('a deleted circle keeps the stored name', () => {
  const row = { targetType: 'circle', targetId: 'c9', circleId: 'c9', circleName: 'Old', targetName: 'Old', metadata: { placePhoto: 'a' } };
  expect(withCurrentCircle(row, new Map([['c9', { name: 'New', deletedAt: '2026-10-01' }]]))).toBe(row);
  expect(withCurrentCircle(row, new Map())).toBe(row);
});
