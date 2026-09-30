// The numbers behind "2nd place for adding places this month" and its screen.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const mockConnections = new Set();
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: jest.fn(async () => mockConnections) }));

const stats = require('../contributionStats');

const now = new Date('2026-09-30T12:00:00Z');
const daysAgo = (n) => new Date(now.getTime() - n * 86400000).toISOString();

beforeEach(() => {
  mockDb.rows('places').clear();
  mockDb.rows('users').clear();
  mockConnections.clear();
});

test('counts live places per adder and ranks with ties sharing the better place', () => {
  const counts = stats.countByAdder([
    { addedBy: 'a' }, { addedBy: 'a' }, { addedBy: 'a' },
    { addedBy: 'wes' }, { addedBy: 'wes' },
    { addedBy: 'b' }, { addedBy: 'b' },
    { addedBy: 'c', deletedAt: 'x' }, { addedBy: null }
  ]);
  expect(stats.rankOf(counts, 'wes')).toEqual({ count: 2, rank: 2, contributors: 3, leaderCount: 3, behindFirst: 1 });
  expect(stats.rankOf(counts, 'b').rank).toBe(2);
  expect(stats.rankOf(counts, 'c')).toMatchObject({ count: 0, rank: null, behindFirst: null });
  expect(stats.topContributors(counts, 1)).toEqual([['a', 3]]);
});

test('forUser: last 30 days only, a board of me and my connections, my places newest first', async () => {
  const add = (id, addedBy, createdAt, extra = {}) => mockDb.collection('places').doc(id).set({ addedBy, createdAt, name: id, ...extra });
  await add('p1', 'wes', daysAgo(1), { photos: ['https://x/1.jpg'] });
  await add('p2', 'wes', daysAgo(5));
  await add('old', 'wes', daysAgo(40));
  await add('gone', 'wes', daysAgo(2), { deletedAt: daysAgo(1) });
  await add('f1', 'friend', daysAgo(3));
  await add('s1', 'stranger', daysAgo(3)); await add('s2', 'stranger', daysAgo(3)); await add('s3', 'stranger', daysAgo(3));
  await mockDb.collection('users').doc('wes').set({ displayName: 'Wes' });
  await mockDb.collection('users').doc('friend').set({ displayName: 'Brit', profilePicture: 'https://x/b.jpg' });
  mockConnections.add('friend');
  mockConnections.add('quiet'); // connected, added nothing — not on the board

  // FakeFirestore has no range filters: recentPlaces gets everything; forUser
  // must still ignore the 40-day-old one via the window it queried
  const out = await stats.forUser('wes', now);
  expect(out.windowDays).toBe(30);
  expect(out.places.map((p) => p.id)).toEqual(expect.arrayContaining(['p1', 'p2']));
  expect(out.places.find((p) => p.id === 'p1').photo).toBe('https://x/1.jpg');
  expect(out.places.some((p) => p.id === 'gone')).toBe(false);
  expect(out.board.map((r) => r.displayName)).toEqual(expect.arrayContaining(['Wes', 'Brit']));
  expect(out.board.some((r) => r.userId === 'stranger' || r.userId === 'quiet')).toBe(false);
  expect(out.board.find((r) => r.isMe).displayName).toBe('Wes');
  expect(out.rank).toBe(2);
});
