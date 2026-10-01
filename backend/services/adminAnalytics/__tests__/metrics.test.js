const m = require('../metrics');

const NOW = new Date('2026-10-01T15:00:00Z');
const daysAgo = (n) => new Date(NOW.getTime() - n * m.DAY).toISOString();

describe('admin metrics', () => {
  test('toDate reads every Firestore date shape', () => {
    expect(m.toDate('2026-10-01T00:00:00Z').toISOString()).toBe('2026-10-01T00:00:00.000Z');
    expect(m.toDate({ _seconds: 1790000000, _nanoseconds: 0 }).getTime()).toBe(1790000000000);
    expect(m.toDate({ toDate: () => new Date(5) }).getTime()).toBe(5);
    expect(m.toDate(null)).toBeNull();
    expect(m.toDate('not a date')).toBeNull();
  });

  test('active users use the latest sign of life', () => {
    const users = [
      { lastActive: daysAgo(0.2) },                         // today
      { lastAppOpenAt: daysAgo(3), lastActive: daysAgo(40) }, // this week
      { lastLogin: daysAgo(20) },                           // this month
      { lastActive: daysAgo(90) },                          // gone
      {}
    ];
    expect(m.activeCounts(users, NOW)).toEqual({ dau: 1, wau: 2, mau: 3 });
  });

  test('perDay fills empty days with zero and ignores out-of-range items', () => {
    const series = m.perDay([{ at: daysAgo(0) }, { at: daysAgo(0) }, { at: daysAgo(2) }, { at: daysAgo(30) }],
      (x) => x.at, new Date(daysAgo(2)), NOW);
    expect(series.map((r) => r.count)).toEqual([1, 0, 2]);
  });

  test('funnel counts only the signup cohort, step by step', () => {
    const users = [
      { id: 'a', createdAt: daysAgo(1), onboardingCompleted: true },
      { id: 'b', createdAt: daysAgo(2), onboardingCompleted: true },
      { id: 'c', createdAt: daysAgo(3) },
      { id: 'old', createdAt: daysAgo(100), onboardingCompleted: true }
    ];
    const counts = new Map([['a', { places: 7, connections: 1 }], ['b', { places: 1, connections: 0 }], ['old', { places: 50, connections: 9 }]]);
    expect(m.funnel(users, counts, new Date(daysAgo(30)), NOW).map((s) => s.count)).toEqual([3, 2, 2, 1, 1]);
  });

  test('retention: share of each signup week active again later', () => {
    const start = new Date('2026-09-07T10:00:00Z'); // a Monday
    const users = [{ id: 'a', createdAt: start.toISOString() }, { id: 'b', createdAt: start.toISOString() }];
    const activity = new Map([
      ['a', [start, new Date(start.getTime() + 8 * m.DAY)]], // week 0 and week 1
      ['b', [start]]                                          // week 0 only
    ]);
    const [row] = m.retention(users, activity, NOW);
    expect(row.week).toBe('2026-09-07');
    expect(row.size).toBe(2);
    expect(row.weeks.slice(0, 3)).toEqual([100, 50, 0]);
  });

  test('postcard money: refunds subtracted, free and failed cards not counted', () => {
    const r = m.postcardMoney([
      { amountCents: 399, status: 'in_transit', createdAt: '2026-09-17T00:00:00Z' },
      { amountCents: 399, status: 'failed', createdAt: '2026-09-17T00:00:00Z', refundedAt: '2026-09-17T00:01:00Z' },
      { amountCents: 399, status: 'in_transit', createdAt: '2026-09-23T00:00:00Z', refundedAt: '2026-09-24T00:00:00Z' },
      { amountCents: 0, status: 'submitted', complimentary: true, createdAt: '2026-09-23T00:00:00Z' }
    ]);
    expect(r).toMatchObject({ count: 2, grossCents: 798, refundedCents: 399, netCents: 399 });
    expect(r.byMonth).toHaveLength(1);
  });

  test('push state labels', () => {
    expect(m.pushState({})).toBe('no_token');
    expect(m.pushState({ deviceTokens: [{}] })).toBe('unknown');
    expect(m.pushState({ deviceTokens: [{}], pushStatus: { status: 'denied' } })).toBe('off');
    expect(m.pushState({ deviceTokens: [{}], pushStatus: { status: 'authorized' } })).toBe('on');
  });

  test('coins by status', () => {
    expect(m.coinSummary([{ coins: 0.5, status: 'pending' }, { coins: 1, status: 'confirmed' }, { coins: 90, status: 'settled' }, { coins: 0.5, status: 'reversed' }]))
      .toMatchObject({ pending: 0.5, confirmed: 1, settled: 90, reversed: 0.5 });
  });
});
