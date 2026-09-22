const { followedUserStats, scoreFor } = require('../followedUserStats');

// A fake Firestore: places per user, and a log of how many queries were in
// flight at once so the test can prove they overlap.
const fakeDb = (placesByUser, clock) => {
  let inFlight = 0; let peak = 0;
  const settle = (value) => new Promise((resolve) => {
    inFlight += 1; peak = Math.max(peak, inFlight);
    setTimeout(() => { inFlight -= 1; resolve(value); }, 5);
  });
  const query = (userId, filters = {}) => ({
    where: (field, op, value) => query(userId, { ...filters, [field]: value }),
    limit: () => query(userId, filters),
    get: () => {
      const all = placesByUser[userId] || [];
      const docs = filters.createdAt ? all.filter((p) => p.createdAt > filters.createdAt) : all;
      return settle({ empty: docs.length === 0, docs });
    },
    count: () => ({ get: () => settle({ data: () => ({ count: (placesByUser[userId] || []).length }) }) }),
  });
  return {
    peak: () => peak,
    collection: () => ({ where: (field, op, userId) => query(userId) }),
  };
};

describe('followedUserStats', () => {
  const now = Date.parse('2026-09-22T12:00:00Z');
  const day = 24 * 60 * 60 * 1000;

  test('scores recent activity and place counts, never mere existence', () => {
    expect(scoreFor({ hasRecentPlace: false, totalPlaces: 0 })).toBe(0);
    expect(scoreFor({ hasRecentPlace: false, totalPlaces: 3 })).toBe(5);
    expect(scoreFor({ hasRecentPlace: false, totalPlaces: 6 })).toBe(10);
    expect(scoreFor({ hasRecentPlace: true, totalPlaces: 11 })).toBe(45);
  });

  test('reports each followed user, with the 7-day window applied', async () => {
    const db = fakeDb({
      active: [{ createdAt: new Date(now - 2 * day) }, { createdAt: new Date(now - 40 * day) }],
      quiet: [{ createdAt: new Date(now - 9 * day) }],
    }, now);
    const stats = await followedUserStats(db, ['active', 'quiet', 'nobody'], now);
    expect(stats.get('active')).toEqual({ hasRecentPlace: true, totalPlaces: 2, score: 35 });
    expect(stats.get('quiet')).toEqual({ hasRecentPlace: false, totalPlaces: 1, score: 5 });
    expect(stats.get('nobody')).toEqual({ hasRecentPlace: false, totalPlaces: 0, score: 0 });
  });

  test('runs the users of a batch at the same time, not one after another', async () => {
    const ids = Array.from({ length: 30 }, (_, i) => `u${i}`);
    const db = fakeDb({}, now);
    await followedUserStats(db, ids, now);
    expect(db.peak()).toBeGreaterThanOrEqual(20);
  });
});
