// Scans that earned nothing, one row each, merged into the owner's Activity
// newest first (Wes, 2026-11-03: check scans against the store's cameras).
const store = { rewardEvents: [], scanAttempts: [] };
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: (name) => {
      const q = { venueId: null, after: null, max: 1000 };
      const api = {
        doc: (id) => ({ set: async (row) => { store[name].push({ id, ...row }); } }),
        where: (_f, _op, v) => { q.venueId = v; return api; },
        orderBy: () => api,
        limit: (n) => { q.max = n; return api; },
        startAfter: (v) => { q.after = v; return api; },
        get: async () => ({
          docs: store[name]
            .filter((r) => r.venueId === q.venueId && (!q.after || r.createdAt < q.after))
            .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
            .slice(0, q.max)
            .map(({ id, ...data }) => ({ id, data: () => data }))
        })
      };
      return api;
    }
  })
}));
const { recordScanAttempt, venueActivityFeed, attemptType } = require('../scanAttempts');

describe('scan attempts', () => {
  beforeEach(() => { store.rewardEvents = []; store.scanAttempts = []; });

  test('types for each reason; earning or unknown reasons are not logged', async () => {
    expect(attemptType('far')).toBeNull();
    expect(attemptType('already_today')).toBe('scan_repeat');
    expect(attemptType('removed')).toBe('scan_removed');
    expect(await recordScanAttempt('u1', { venueId: 'v1' }, { reason: undefined })).toBeNull();
    expect(store.scanAttempts).toHaveLength(0);
  });

  test('every attempt is its own row with a time', async () => {
    const venue = { venueId: 'v1', venueName: 'Bakery' };
    await recordScanAttempt('u1', venue, { reason: 'already_today', location: 'near' });
    await recordScanAttempt('u1', venue, { reason: 'already_today', location: 'near' });
    expect(store.scanAttempts).toHaveLength(2);
    expect(store.scanAttempts[0]).toMatchObject({ userId: 'u1', venueId: 'v1', type: 'scan_repeat', points: 0, location: 'near' });
    expect(store.scanAttempts[0].createdAt).toMatch(/^\d{4}-\d\d-\d\dT/);
    expect(store.scanAttempts[0].id).not.toBe(store.scanAttempts[1].id);
  });

  test('the feed merges both lists newest first and pages by time', async () => {
    store.rewardEvents.push(
      { id: 'e1', venueId: 'v1', type: 'venue_visit', createdAt: '2026-11-03T10:00:00.000Z' },
      { id: 'e2', venueId: 'v1', type: 'redemption', createdAt: '2026-11-03T12:00:00.000Z' },
      { id: 'other', venueId: 'v2', type: 'venue_visit', createdAt: '2026-11-03T13:00:00.000Z' }
    );
    store.scanAttempts.push({ id: 'a1', venueId: 'v1', type: 'scan_repeat', createdAt: '2026-11-03T11:00:00.000Z' });
    const first = await venueActivityFeed('v1', 'rewardEvents', { limit: 2 });
    expect(first.map((r) => r.id)).toEqual(['e2', 'a1']);
    const next = await venueActivityFeed('v1', 'rewardEvents', { limit: 2, before: first[1].createdAt });
    expect(next.map((r) => r.id)).toEqual(['e1']);
  });
});
