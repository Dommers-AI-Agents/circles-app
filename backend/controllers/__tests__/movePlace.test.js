// Moving a place between circles is organization, not news (Wes, 2026-11-24:
// three moves showed up in Recent Activity as "added three places"). A move
// writes no activity row and tells no connection; the rows the place already
// has follow it to the new circle.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  admin: { firestore: { FieldPath: { documentId: () => '__name__' }, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue } },
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/notificationService', () => ({ sendToUserWithRecord: jest.fn(async () => {}) }));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn(), sendEvent: jest.fn() }));
jest.mock('../../services/userStatsCache', () => ({ getPlaceCountMap: jest.fn(async () => new Map()) }));
jest.mock('../../services/emailService', () => ({ sendEmail: jest.fn(async () => {}) }));
jest.mock('../../services/adminAlerts', () => ({ alertAdmin: jest.fn(async () => true) }));
jest.mock('../../services/backgroundAggregationService', () => ({}));
jest.mock('../../services/cacheInvalidationService', () => ({}));
jest.mock('../../services/activityFeedService', () => ({ fetchActivitiesByActors: jest.fn(async () => []) }));
jest.mock('../../services/globalPlaceResolver', () => ({
  findCanonicalByNameAndLocation: jest.fn(async () => null),
  createGlobalPlaceFromDetails: jest.fn(async () => ({ resolvedId: 'gp1' }))
}));
jest.mock('../../services/rewardService', () => ({ findVenueByPlace: jest.fn(async () => null) }));
jest.mock('../../services/requestDeduplicator', () => ({}));
jest.mock('../../services/circleLocationSummary', () => ({ indexPlaceRemoved: jest.fn(), indexPlaceMoved: jest.fn() }));
jest.mock('../../services/placeCache', () => ({ clear: jest.fn(), get: jest.fn(), set: jest.fn() }));

const { movePlace } = require('../places/placeController');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const fail = (e) => { throw e; };
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const row = (col, id) => mockDb.rows(col).get(id);

beforeEach(async () => {
  for (const name of ['circles', 'places', 'connections', 'activities']) mockDb.rows(name).clear();
  jest.clearAllMocks();
  await put('circles', 'food', { name: 'Food', owner: 'u1', privacy: 'public', places: ['p1'], placesCount: 1 });
  await put('circles', 'date', { name: 'Date Night', owner: 'u1', privacy: 'public', places: [], placesCount: 0 });
  await put('places', 'p1', { name: 'Optimist Hall', address: '1115 N Brevard St', circleId: 'food', addedBy: 'u1',
    privacy: 'followCircle', globalPlaceId: 'gp-optimist', deletedAt: null });
  await put('connections', 'c-u1-u2', { userId: 'u1', connectedUserId: 'u2', status: 'accepted', recentActivity: [] });
  await put('activities', 'a-added', { type: 'place_added', actorId: 'u1', targetType: 'place', targetId: 'p1', targetName: 'Optimist Hall',
    circleId: 'food', circleName: 'Food', timestamp: '2026-11-01T10:00:00.000Z', metadata: {} });
  await put('activities', 'a-liked', { type: 'place_liked', actorId: 'u2', targetType: 'place', targetId: 'p1', targetName: 'Optimist Hall',
    circleId: 'food', circleName: 'Food', timestamp: '2026-11-02T10:00:00.000Z', metadata: {} });
  await put('activities', 'a-other', { type: 'place_added', actorId: 'u1', targetType: 'place', targetId: 'p9', targetName: 'Elsewhere',
    circleId: 'food', circleName: 'Food', timestamp: '2026-11-03T10:00:00.000Z', metadata: {} });
});

const move = async (placeId, targetCircleId) => {
  const r = res();
  await movePlace({ params: { id: placeId }, user: { uid: 'u1' }, body: { targetCircleId } }, r, fail);
  return r;
};

test('a move writes no activity row and tells no connection', async () => {
  const r = await move('p1', 'date');
  expect(r.status).toHaveBeenCalledWith(200);
  expect(r.json.mock.calls[0][0]).toMatchObject({ success: true, place: { id: 'p1', circleId: 'date' } });

  expect([...mockDb.rows('activities').keys()].sort()).toEqual(['a-added', 'a-liked', 'a-other']);
  expect(row('connections', 'c-u1-u2').recentActivity).toEqual([]);
  expect(row('connections', 'c-u1-u2').hasNewActivity).toBeUndefined();
});

test('the place and both circles reflect the move', async () => {
  await move('p1', 'date');
  expect(row('places', 'p1').circleId).toBe('date');
  expect(row('circles', 'food')).toMatchObject({ places: [], placesCount: 0 });
  expect(row('circles', 'date')).toMatchObject({ places: ['p1'], placesCount: 1 });
});

test("the place's existing rows follow it to the new circle; other places' rows stay", async () => {
  await move('p1', 'date');
  expect(row('activities', 'a-added')).toMatchObject({ circleId: 'date', circleName: 'Date Night', timestamp: '2026-11-01T10:00:00.000Z' });
  expect(row('activities', 'a-liked')).toMatchObject({ circleId: 'date', circleName: 'Date Night' });
  expect(row('activities', 'a-other')).toMatchObject({ circleId: 'food', circleName: 'Food' });
});

test('moving onto a circle that already holds the venue merges without a new row', async () => {
  await put('places', 'p2', { name: 'Optimist Hall', address: '1115 N Brevard St', circleId: 'date', addedBy: 'u1',
    privacy: 'followCircle', globalPlaceId: 'gp-optimist', deletedAt: null });
  await put('circles', 'date', { name: 'Date Night', owner: 'u1', privacy: 'public', places: ['p2'], placesCount: 1 });

  const r = await move('p1', 'date');
  expect(r.json.mock.calls[0][0]).toMatchObject({ success: true, merged: true });
  expect(row('places', 'p1').deletedAt).toBeTruthy();
  expect([...mockDb.rows('activities').keys()].sort()).toEqual(['a-added', 'a-liked', 'a-other']);
  expect(row('connections', 'c-u1-u2').recentActivity).toEqual([]);
});
