// Inner Circle workout feed: only grantors who are still connected show up,
// posts are bucketed by month, and the client's summary is validated.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const mockGrantors = new Set();
const mockConnections = new Set();
jest.mock('../../utils/networkAccess', () => ({
  getInnerCircleGrantorIds: jest.fn(async () => mockGrantors),
  getConnectedUserIds: jest.fn(async () => mockConnections)
}));

const feed = require('../workoutFeedService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const summary = (overrides = {}) => ({
  name: 'Push', startedAt: '2026-09-19T11:00:00.000Z', durationSeconds: 2700, completedSets: 4,
  exercises: [{ name: 'Bench Press', sets: 2, bestSet: '195 lb × 5', isPR: true }],
  cardio: [{ name: 'Treadmill', minutes: 10, detail: '10 min · 1 mi' }],
  prCount: 1, unit: 'lb', ...overrides
});

beforeEach(() => {
  mockDb.rows(COLLECTIONS.WORKOUT_POSTS).clear();
  mockDb.rows(COLLECTIONS.USERS).clear();
  mockGrantors.clear();
  mockConnections.clear();
});

test('share validates, trims and replaces the same workout', async () => {
  await expect(feed.share({ userId: 'b', summary: null })).rejects.toMatchObject({ code: 'bad_summary' });
  await expect(feed.share({ userId: 'b', summary: summary({ exercises: [], cardio: [] }) })).rejects.toMatchObject({ code: 'bad_summary' });
  const first = await feed.share({ userId: 'b', summary: summary({ name: ' '.repeat(3) + 'X'.repeat(200), exercises: [{ name: 'Bench', sets: 500, bestSet: 'y', isPR: 'yes' }] }) });
  const row = mockDb.rows(COLLECTIONS.WORKOUT_POSTS).get(first.postId);
  expect(row.summary.name).toHaveLength(80);
  expect(row.summary.exercises[0]).toEqual({ name: 'Bench', sets: 99, bestSet: 'y', isPR: true });
  expect(row.summary.unit).toBe('lb');
  const second = await feed.share({ userId: 'b', summary: summary() });
  expect(second.postId).toBe(first.postId); // same workout, one post
  expect(mockDb.rows(COLLECTIONS.WORKOUT_POSTS).size).toBe(1);
});

test('feed shows grantors who are still connected, newest first, with names', async () => {
  await mockDb.collection(COLLECTIONS.USERS).doc('brit').set({ displayName: 'Brittany', profilePicture: 'https://x/b.jpg' });
  await mockDb.collection(COLLECTIONS.USERS).doc('ex').set({ displayName: 'Ex' });
  await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-18T11:00:00Z', name: 'Legs' }) });
  await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-19T11:00:00Z', name: 'Push' }) });
  await feed.share({ userId: 'ex', summary: summary({ name: 'Should not show' }) });
  await feed.share({ userId: 'stranger', summary: summary({ name: 'Nor this' }) });
  mockGrantors.add('brit'); mockGrantors.add('ex');
  mockConnections.add('brit'); // ex granted access once but is no longer connected

  const posts = await feed.feed('wes', new Date('2026-09-19T12:00:00Z'));
  expect(posts.map((p) => p.summary.name)).toEqual(['Push', 'Legs']);
  expect(posts[0]).toMatchObject({ userId: 'brit', userName: 'Brittany', avatarUrl: 'https://x/b.jpg' });
  mockGrantors.clear();
  expect(await feed.feed('nobody')).toEqual([]); // no grantors at all → nothing
});

test('feed spans this month and last, and drops old posts', async () => {
  mockGrantors.add('brit'); mockConnections.add('brit');
  await mockDb.collection(COLLECTIONS.USERS).doc('brit').set({ displayName: 'Brittany' });
  await feed.share({ userId: 'brit', summary: summary({ name: 'Recent' }) });
  // A post from six weeks ago in a different month bucket.
  await mockDb.collection(COLLECTIONS.WORKOUT_POSTS).doc('brit_old').set({
    userId: 'brit', summary: summary({ name: 'Old' }), monthKey: '2026-08', createdAt: '2026-08-01T10:00:00.000Z'
  });
  await mockDb.collection(COLLECTIONS.WORKOUT_POSTS).doc('brit_lastmonth').set({
    userId: 'brit', summary: summary({ name: 'Last month' }), monthKey: '2026-08', createdAt: '2026-08-28T10:00:00.000Z'
  });
  const posts = await feed.feed('wes', new Date('2026-09-19T12:00:00Z'));
  expect(posts.map((p) => p.summary.name)).toEqual(['Recent', 'Last month']);
});

test('helpers', () => {
  expect(feed.monthKeyOf(new Date('2026-09-19T23:59:00Z'))).toBe('2026-09');
  expect(feed.normalizeSummary(summary({ unit: 'stone' })).unit).toBe('lb');
});
