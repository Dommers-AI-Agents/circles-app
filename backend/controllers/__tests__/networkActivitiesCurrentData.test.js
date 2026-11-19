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
const { withCurrentCircle, withCurrentVenue } = require('../../services/activityFeedOverlay');

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
  for (const name of ['users', 'circles', 'activities', 'activityReactions', 'connections', 'places', 'globalPlaces']) mockDb.rows(name).clear();
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
  // Written before the venue had a picture: the feed fills it from the venue record now
  await put('activities', 'a3', {
    type: 'place_added', actorId: 'alex', targetType: 'place', targetId: 'p3', targetName: 'Sky Harbor',
    circleId: 'c1', circleName: 'Food', timestamp: '2026-10-22T10:00:00.000Z',
    metadata: { placePhoto: null, placePrivacy: 'public' }
  });
  await put('places', 'p3', { name: 'Sky Harbor', addedBy: 'alex', privacy: 'public', globalPlaceId: 'g3', photos: [] });
  await put('globalPlaces', 'g3', { name: 'Sky Harbor', coverPhotoUrl: 'https://x/venue-cover.jpg', category: 'airport',
    location: { type: 'Point', coordinates: [-112.01, 33.43] } });
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

test('a place row without a picture or pin gets its venue\'s photo, location and category (2026-11-19)', async () => {
  const body = await run();
  const row = body.activities.find((a) => (a.id || a._id) === 'a3');
  expect(row.metadata).toMatchObject({ placePhoto: 'https://x/venue-cover.jpg', latitude: 33.43, longitude: -112.01, placeCategory: 'airport' });
  // A row that already has its picture keeps it
  const kept = body.activities.find((a) => (a.id || a._id) === 'a2');
  expect(kept.metadata.placePhoto).toBe('https://x/place.jpg');
});

test('withCurrentVenue never overwrites a stored value and leaves non-place rows alone', () => {
  const venuesById = new Map([['g1', { coverPhotoUrl: 'https://x/v.jpg', category: 'cafe', location: { coordinates: [-80.8, 35.2] } }]]);
  const savesById = new Map([['p1', { globalPlaceId: 'g1', photos: ['https://x/own.jpg'] }]]);
  const stored = { targetType: 'place', targetId: 'p1', metadata: { placePhoto: 'https://x/mine.jpg', latitude: 1, longitude: 2, placeCategory: 'bar' } };
  expect(withCurrentVenue(stored, { venuesById, savesById })).toBe(stored);
  const bare = { targetType: 'place', targetId: 'p1', metadata: {} };
  expect(withCurrentVenue(bare, { venuesById, savesById }).metadata).toEqual({ placePhoto: 'https://x/own.jpg', latitude: 35.2, longitude: -80.8, placeCategory: 'cafe' });
  const byVenueId = { targetType: 'global_place', targetId: 'photo9', metadata: { globalPlaceId: 'g1' } };
  expect(withCurrentVenue(byVenueId, { venuesById, savesById }).metadata.placePhoto).toBe('https://x/v.jpg');
  const circleRow = { targetType: 'circle', targetId: 'c1', metadata: {} };
  expect(withCurrentVenue(circleRow, { venuesById, savesById })).toBe(circleRow);
  const profile = { targetType: 'user', targetId: 'u1', metadata: {} };
  expect(withCurrentVenue(profile, { venuesById, savesById })).toBe(profile);
});
