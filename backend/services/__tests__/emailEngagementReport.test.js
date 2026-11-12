const { summarize } = require('../emailEngagementReport');

const NOW = new Date('2026-11-12T15:00:00Z');
const at = (daysAgo, h = 10) => new Date(NOW.getTime() - daysAgo * 86400000 - (15 - h) * 3600000).toISOString();

describe('emailEngagementReport.summarize', () => {
  const events = [
    { event: 'click', kind: 'welcome', uid: 'a', email: 'a@x', url: 'https://f/1', at: at(0) },
    { event: 'click', kind: 'welcome', uid: 'a', email: 'a@x', url: 'https://f/2', at: at(0, 9) },
    { event: 'click', kind: 'welcome', uid: 'b', email: 'b@x', url: 'https://f/1', at: at(2) },
    { event: 'open', kind: 'welcome', uid: 'a', email: 'a@x', at: at(0) },
    { event: 'open', kind: 'welcome', uid: 'c', email: 'c@x', at: at(1) },
    { event: 'click', kind: 'new_follower', uid: null, email: 'guest@x', url: 'https://f/3', at: at(5) },
    { event: 'click', kind: 'welcome', uid: 'z', email: 'z@x', url: 'https://f/1', at: at(45) } // outside the window's byDay, still counted in kinds? no: caller filters by window
  ];

  test('per kind: sends, distinct clickers, clicks, opens and a click rate', () => {
    const r = summarize(events.slice(0, 6), { welcome: 10, new_follower: 4, weekly_letter: 7 }, { now: NOW, days: 30 });
    expect(r.kinds.map((k) => k.kind)).toEqual(['welcome', 'weekly_letter', 'new_follower']);
    const w = r.kinds[0];
    expect(w).toEqual({ kind: 'welcome', sent: 10, clicks: 3, clickers: 2, opens: 2, openers: 2, clickRate: 0.2 });
    expect(r.kinds[1]).toEqual(expect.objectContaining({ sent: 7, clicks: 0, clickRate: 0 }));
    expect(r.kinds[2]).toEqual(expect.objectContaining({ sent: 4, clicks: 1, clickers: 1, clickRate: 0.25 }));
    expect(r.totals).toEqual({ sent: 21, clicks: 4, opens: 2, clickers: 3 });
  });

  test('a kind with clicks but no counted sends has no rate rather than a wrong one', () => {
    const r = summarize([{ event: 'click', kind: 'old', uid: 'a', at: at(0) }], {}, { now: NOW });
    expect(r.kinds[0].clickRate).toBeNull();
  });

  test('byDay covers the window newest-last and recent clicks come newest-first', () => {
    const r = summarize(events.slice(0, 6), {}, { now: NOW, days: 7 });
    expect(r.byDay).toHaveLength(7);
    expect(r.byDay[6]).toEqual({ day: '2026-11-12', clicks: 2, opens: 1 });
    expect(r.byDay[4]).toEqual({ day: '2026-11-10', clicks: 1, opens: 0 });
    expect(r.recentClicks.map((c) => c.url)).toEqual(['https://f/1', 'https://f/2', 'https://f/1', 'https://f/3']);
    expect(r.from).toBe('2026-11-06');
  });
});
