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
// Which of each grantor's lists the viewer is on; a grantor with no entry
// here is on "some list" without a name, as before lists existed.
const mockLists = new Map();
jest.mock('../../utils/networkAccess', () => ({
  getInnerCircleGrantorIds: jest.fn(async () => mockGrantors),
  getInnerCircleGrantorLists: jest.fn(async () => new Map([...mockGrantors].map((id) => [id, mockLists.get(id) || new Set()]))),
  getConnectedUserIds: jest.fn(async () => mockConnections)
}));

const feed = require('../workoutFeedService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

// The month bucket comes from the share time; pin it so these don't break
// when the real calendar moves on (they did on 2026-10-01)
const SEPT = new Date('2026-09-19T11:30:00Z');

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
  mockLists.clear();
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
  await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-18T11:00:00Z', name: 'Legs' }), now: SEPT });
  await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-19T11:00:00Z', name: 'Push' }), now: SEPT });
  await feed.share({ userId: 'ex', summary: summary({ name: 'Should not show' }), now: SEPT });
  await feed.share({ userId: 'stranger', summary: summary({ name: 'Nor this' }), now: SEPT });
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
  await feed.share({ userId: 'brit', summary: summary({ name: 'Recent' }), now: SEPT });
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

test('a post shared to one named list reaches that list only', async () => {
  mockGrantors.add('b'); mockConnections.add('b');
  mockDb.rows(COLLECTIONS.USERS).set('b', { displayName: 'B' });
  await feed.share({ userId: 'b', summary: summary({ name: 'Family only' }), audienceListId: 'family' });
  await feed.share({ userId: 'b', summary: summary({ name: 'Everyone', startedAt: '2026-09-19T12:00:00.000Z' }) });
  // Viewer is on b's gym list, not family.
  mockLists.set('b', new Set(['gym']));
  expect((await feed.feed('viewer')).map((p) => p.summary.name)).toEqual(['Everyone']);
  mockLists.set('b', new Set(['family']));
  expect((await feed.feed('viewer')).map((p) => p.summary.name).sort()).toEqual(['Everyone', 'Family only']);
  // Junk list ids are stored as none, not as a list nobody is on.
  const r = await feed.share({ userId: 'b', summary: summary({ startedAt: '2026-09-18T12:00:00.000Z' }), audienceListId: '  ' });
  expect(r.audienceListId).toBeNull();
});

test('connections-audience posts reach every connection; Inner Circle posts only grantors', async () => {
  await feed.share({ userId: 'brit', summary: summary({ name: 'Open', startedAt: '2026-09-18T11:00:00Z' }), audience: 'connections' });
  await feed.share({ userId: 'brit', summary: summary({ name: 'Close', startedAt: '2026-09-19T11:00:00Z' }) });
  mockConnections.add('brit'); // connected, NOT on her Inner Circle
  const seen = (await feed.feed('viewer')).map((p) => p.summary.name);
  expect(seen).toEqual(['Open']);
  mockGrantors.add('brit');
  expect((await feed.feed('viewer')).map((p) => p.summary.name).sort()).toEqual(['Close', 'Open']);
});

test('getPost: the author, their audience, and nobody else', async () => {
  const open = await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-18T11:00:00Z' }), audience: 'connections' });
  const close = await feed.share({ userId: 'brit', summary: summary({ startedAt: '2026-09-19T11:00:00Z' }), audienceListId: 'family' });
  await expect(feed.getPost(open.postId, 'stranger')).rejects.toMatchObject({ code: 'not_found' });
  mockConnections.add('brit');
  expect((await feed.getPost(open.postId, 'viewer')).postId).toBe(open.postId);
  await expect(feed.getPost(close.postId, 'viewer')).rejects.toMatchObject({ code: 'not_found' });
  mockGrantors.add('brit'); mockLists.set('brit', new Set(['work']));
  await expect(feed.getPost(close.postId, 'viewer')).rejects.toMatchObject({ code: 'not_found' });
  mockLists.set('brit', new Set(['family']));
  expect((await feed.getPost(close.postId, 'viewer')).summary.name).toBe('Push');
  mockConnections.clear();
  expect((await feed.getPost(close.postId, 'brit')).userId).toBe('brit');
  await expect(feed.getPost('missing', 'brit')).rejects.toMatchObject({ code: 'not_found' });
});

test('share keeps a copyable routine and writes one feed row per workout', async () => {
  const rows = [];
  const onFirstShare = async (post) => rows.push(post);
  const routine = [
    { exerciseId: 'overhead_press', name: 'Overhead Press', muscleGroup: 'Shoulders', sets: 3, reps: 10, weight: 50 },
    { exerciseId: 'custom-1', name: 'Shrug', muscleGroup: 'Back', sets: 99, reps: 20, weight: -5 }
  ];
  const first = await feed.share({ userId: 'b', summary: summary({ routine }), audience: 'connections', onFirstShare });
  const stored = mockDb.rows(COLLECTIONS.WORKOUT_POSTS).get(first.postId);
  expect(stored.audience).toBe('connections');
  expect(stored.audienceListId).toBeNull();
  expect(stored.summary.routine[0]).toEqual(routine[0]);
  expect(stored.summary.routine[1]).toMatchObject({ sets: 20, weight: null });
  await feed.share({ userId: 'b', summary: summary({ routine }), audience: 'connections', onFirstShare });
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({ postId: first.postId, audience: 'connections' });
  // An unknown audience falls back to the Inner Circle, never wider
  const odd = await feed.share({ userId: 'c', summary: summary(), audience: 'everyone' });
  expect(odd.audience).toBe('innerCircle');
});

describe('texted link', () => {
  beforeEach(() => mockDb.rows(COLLECTIONS.WORKOUT_LINKS).clear());

  test('anyone with the link can open the workout; nobody\'s feed shows it', async () => {
    const { token, url, postId } = await feed.createLink({ userId: 'wes', summary: summary(), now: SEPT });
    expect(url).toBe(`https://api.favcircles.com/app/workout/${token}`);
    expect(token).toMatch(/^[A-Za-z0-9_-]{22}$/);
    // A stranger (not connected) opens it by the token
    const post = await feed.getPost(token, 'stranger');
    expect(post).toMatchObject({ postId, userId: 'wes', summary: { name: 'Push' } });
    // …but not by the post id, and not in the feed
    await expect(feed.getPost(postId, 'stranger')).rejects.toMatchObject({ status: 404 });
    mockConnections.add('wes');
    mockGrantors.add('wes');
    expect(await feed.feed('friend', SEPT)).toEqual([]);
  });

  test('sharing the same workout again reuses its link, and a feed share keeps it', async () => {
    const first = await feed.createLink({ userId: 'wes', summary: summary(), now: SEPT });
    const again = await feed.createLink({ userId: 'wes', summary: summary(), now: SEPT });
    expect(again.token).toBe(first.token);
    await feed.share({ userId: 'wes', summary: summary(), audience: 'connections', now: SEPT });
    expect((await feed.getPost(first.token, 'stranger')).summary.name).toBe('Push');
  });

  test('a made-up token finds nothing', async () => {
    await expect(feed.getPost('AAAAAAAAAAAAAAAAAAAAAA', 'stranger')).rejects.toMatchObject({ status: 404 });
    expect(await feed.postByLink('../etc')).toBeNull();
  });
});
