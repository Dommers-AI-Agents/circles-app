// "My check-ins": one row per venue, newest first, from the stats buckets.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) }),
  FieldValue: {}
}));
jest.mock('../globalPlaceResolver', () => ({
  ensureGlobalPlaceLink: jest.fn(),
  findCanonicalByNameAndLocation: jest.fn()
}));

const { placeRows, totals } = require('../checkInHistory');

const NOW = Date.parse('2026-11-09T20:00:00Z');
const bucket = (id, data) => ({ id, data });

test('rows carry the venue name and cover, newest check-in first', () => {
  const rows = placeRows([
    bucket('g1', { count: 7, firstCheckInAt: '2026-01-05T11:00:00Z', lastCheckInAt: '2026-09-05T11:00:00Z', placeName: 'Crunch (typed)', lastPlaceId: 'p1' }),
    bucket('g2', { count: 2, firstCheckInAt: '2026-10-01T11:00:00Z', lastCheckInAt: '2026-11-08T11:00:00Z', placeName: 'Muraya', lastPlaceId: 'p2' })
  ], new Map([
    ['g1', { name: 'Crunch Fitness', address: '1 Main St', category: 'fitness', photos: [{ url: 'https://x/a.jpg' }] }],
    ['g2', { name: 'Muraya', coverPhotoUrl: 'https://x/cover.jpg', photos: [] }]
  ]), [], NOW);
  expect(rows.map((r) => r.globalPlaceId)).toEqual(['g2', 'g1']);
  expect(rows[1]).toMatchObject({ name: 'Crunch Fitness', address: '1 Main St', category: 'fitness', photoUrl: 'https://x/a.jpg', count: 7, placeId: 'p1', importedCount: 0 });
  expect(rows[0].photoUrl).toBe('https://x/cover.jpg');
});

test('a venue nobody can read any more still shows by its remembered name', () => {
  const rows = placeRows([bucket('gone', { count: 1, lastCheckInAt: '2026-11-01T11:00:00Z', firstCheckInAt: '2026-11-01T11:00:00Z', placeName: 'Tremont' })], new Map(), [], NOW);
  expect(rows[0]).toMatchObject({ name: 'Tremont', photoUrl: null, placeId: null });
});

test('a Swarm-only bucket (no top-level dates) is listed and sorted by its imported history', () => {
  const rows = placeRows([
    bucket('fav', { count: 1, firstCheckInAt: '2026-06-01T11:00:00Z', lastCheckInAt: '2026-06-01T11:00:00Z', placeName: 'A' }),
    bucket('swarm', { placeName: 'B', imported: { swarm: { count: 12, firstCheckInAt: '2019-01-01T00:00:00Z', lastCheckInAt: '2026-08-01T00:00:00Z' } } })
  ], new Map(), [], NOW);
  expect(rows.map((r) => r.globalPlaceId)).toEqual(['swarm', 'fav']);
  expect(rows[0]).toMatchObject({ count: 12, importedCount: 12, lastCheckInAt: '2026-08-01T00:00:00Z' });
});

test('empty buckets are skipped; "lately" counts the last 30 days per venue', () => {
  const rows = placeRows([
    bucket('g1', { count: 3, firstCheckInAt: '2026-09-01T11:00:00Z', lastCheckInAt: '2026-11-08T11:00:00Z' }),
    bucket('empty', { count: 0 })
  ], new Map(), [
    { startTime: '2026-11-08T11:00:00Z', globalPlaceId: 'g1' },
    { startTime: '2026-10-20T11:00:00Z', globalPlaceId: 'g1' },
    { startTime: '2026-09-01T11:00:00Z', globalPlaceId: 'g1' }, // too old
    { startTime: '2026-11-01T11:00:00Z' } // unresolved venue
  ], NOW);
  expect(rows).toHaveLength(1);
  expect(rows[0].recentCount).toBe(2);
  expect(totals(rows)).toEqual({ total: 3, places: 1, recent: 2 });
});
