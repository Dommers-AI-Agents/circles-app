// Pure halves of the weekly summary: when it fires, what counts as activity,
// coin copy. Firestore/push/email are mocked out; nothing is sent.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) }),
  FieldValue: {}
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn() }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn(), isConfigured: true }));

const service = require('../dailySummaryService');

const prefs = (summaryTime, timezone) => ({ notificationPreferences: { summaryTime, timezone } });

describe('isUsersSummaryHour (weekly)', () => {
  // 2026-09-14 is a Monday. 16:00Z = 12:00 New York, 09:00 Los Angeles.
  const mondayNoonET = new Date('2026-09-14T16:00:00Z');
  const tuesdayNoonET = new Date('2026-09-15T16:00:00Z');

  it('fires on Monday at the preferred local hour', () => {
    expect(service.isUsersSummaryHour(prefs('12:00', 'America/New_York'), mondayNoonET)).toBe(true);
  });
  it('is timezone-aware: noon ET is 9am in LA', () => {
    expect(service.isUsersSummaryHour(prefs('12:00', 'America/Los_Angeles'), mondayNoonET)).toBe(false);
    expect(service.isUsersSummaryHour(prefs('09:00', 'America/Los_Angeles'), mondayNoonET)).toBe(true);
  });
  it('does not fire on other weekdays even at the right hour', () => {
    expect(service.isUsersSummaryHour(prefs('12:00', 'America/New_York'), tuesdayNoonET)).toBe(false);
  });
  it('defaults to 12:00 New York and survives a bad timezone', () => {
    expect(service.isUsersSummaryHour({}, mondayNoonET)).toBe(true);
    expect(service.isUsersSummaryHour(prefs('12:00', 'Mars/Olympus'), mondayNoonET)).toBe(true);
  });
  it('crosses the date line correctly: Monday 10:00 in Tokyo is Sunday in New York', () => {
    const tokyoMonday10 = new Date('2026-09-14T01:00:00Z');
    expect(service.isUsersSummaryHour(prefs('10:00', 'Asia/Tokyo'), tokyoMonday10)).toBe(true);
    expect(service.isUsersSummaryHour(prefs('21:00', 'America/New_York'), tokyoMonday10)).toBe(false);
  });
});

describe('isWithinWeeklyWindow', () => {
  const now = new Date('2026-09-21T16:00:00Z').getTime(); // Monday noon ET
  it('ignores the retired daily stamp — a doc the daily job stamped last Tuesday still gets its first Monday', () => {
    expect(service.isWithinWeeklyWindow({ lastDailySummary: '2026-09-19T16:00:00Z' }, now)).toBe(false);
    expect(service.isWithinWeeklyWindow({}, now)).toBe(false);
    expect(service.isWithinWeeklyWindow(null, now)).toBe(false);
  });
  it('dedupes within 6 days of the weekly stamp and reopens after', () => {
    expect(service.isWithinWeeklyWindow({ lastWeeklySummary: '2026-09-21T15:00:00Z' }, now)).toBe(true);
    expect(service.isWithinWeeklyWindow({ lastWeeklySummary: '2026-09-16T16:00:00Z' }, now)).toBe(true);  // 5 days
    expect(service.isWithinWeeklyWindow({ lastWeeklySummary: '2026-09-14T16:00:00Z' }, now)).toBe(false); // last Monday
  });
});

describe('hasActivity', () => {
  const quiet = { newPlaces: 0, newConnections: 0, unreadMessages: 0, placeComments: 0, placeLikes: 0, favCoins: null };
  it('is quiet with nothing to report', () => {
    expect(service.hasActivity(quiet)).toBe(false);
    expect(service.hasActivity({ ...quiet, favCoins: { earnedThisWeek: 0 } })).toBe(false);
  });
  it('counts FavCoins earned this week as activity', () => {
    expect(service.hasActivity({ ...quiet, favCoins: { earnedThisWeek: 0.5 } })).toBe(true);
  });
  it('counts network activity', () => {
    expect(service.hasActivity({ ...quiet, newPlaces: 1 })).toBe(true);
  });
});

describe('formatCoins', () => {
  it('pluralizes as FavCoins, never FavCoin\'s', () => {
    expect(service.formatCoins(1)).toBe('1 FavCoin');
    expect(service.formatCoins(2)).toBe('2 FavCoins');
    expect(service.formatCoins(0)).toBe('0 FavCoins');
    expect(service.formatCoins(12.5)).toBe('12.5 FavCoins');
    expect(service.formatCoins(0.05)).toBe('0.05 FavCoins');
    expect(service.formatCoins(3.10000001)).toBe('3.1 FavCoins');
  });
});

describe('buildSummaryNotification', () => {
  it('is titled as a weekly summary and mentions coins earned', () => {
    const n = service.buildSummaryNotification({
      newPlaces: 3, newPlacesByCategory: { cafe: 2, bar: 1 }, newConnections: 0, unreadMessages: 0,
      placeComments: 0, placeLikes: 0, topContributors: [], favCoins: { earnedThisWeek: 2.5 }
    }, { displayName: 'Wes' });
    expect(n.title).toBe('Your Weekly Summary');
    expect(n.type).toBe('daily_summary'); // shipped iOS routes on this type
    expect(n.body).toContain('3 new places');
    expect(n.body).toContain('+2.5 FavCoins earned');
    expect(n.subtitle).toMatch(/^Week ending /);
  });
});

describe('email HTML', () => {
  it('carries the Cactus blockchain 🌵 statement and where to find coins', () => {
    const html = service.buildSummaryEmailHtml(
      { displayName: 'Wes' },
      { newPlaces: 0, newPlacesByCategory: {}, newConnections: 0, unreadMessages: 0, placeComments: 0, placeLikes: 0,
        topContributors: [], favCoins: { confirmedCoins: 41.25, pendingCoins: 0.5, lifetimeCoins: 60, settledOnChain: 0, hasWallet: false, earnedThisWeek: 3, earnEventsThisWeek: 4 } },
      { title: 'Your Weekly Summary' }
    );
    expect(html).toContain('Your Weekly Summary');
    expect(html).toContain('this week');
    expect(html).toContain('41.25 FavCoins available');
    expect(html).toContain('+3 FavCoins earned this week (4 rewards)');
    expect(html).toContain('Cactus blockchain 🌵');
    expect(html).toContain('Rewards → Piggy Bank');
    expect(html).toContain('path=create-wallet');
    expect(html).not.toContain("FavCoin's");
    expect(html).not.toContain('yesterday');
  });
});
