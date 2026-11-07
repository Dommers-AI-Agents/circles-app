// The week's recap emails are spread out (Wes, 2026-11-06): letter Wednesday,
// "People you may know" Thursday, the map every other Saturday, and never
// two of them a day apart.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../models/FirestoreModels', () => ({ COLLECTIONS: { USERS: 'users' } }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn() }));
jest.mock('staticmaps', () => jest.fn());
jest.mock('../storage', () => ({ uploadImage: jest.fn() }));

const { recentlyEmailed } = require('../emailCadence');
const { digestSkipReason } = require('../mapDigestService');
const { monthStats, hasActivity } = require('../venueReportsTask');

const now = new Date('2026-11-07T15:00:00Z').getTime(); // a Saturday
const daysAgo = (n) => new Date(now - n * 86400000).toISOString();
const user = (overrides) => ({ id: 'u1', email: 'a@example.com', ...overrides });

test('a recap email in the last two days holds the next one', () => {
  expect(recentlyEmailed(user({ lastWeeklySummary: daysAgo(1) }), now)).toBe(true);
  expect(recentlyEmailed(user({ followSuggestionEmail: { lastSentAt: daysAgo(1.5) } }), now)).toBe(true);
  expect(recentlyEmailed(user({ lastWeeklySummary: daysAgo(3) }), now)).toBe(false);
  expect(recentlyEmailed(user({}), now)).toBe(false);
});

test('the map email: every other week, never right after Thursday, never to test accounts', () => {
  expect(digestSkipReason(user({}), now)).toBeNull();
  expect(digestSkipReason(user({ mapDigest: { lastSentAt: daysAgo(7) } }), now)).toBe('sent_recently');
  expect(digestSkipReason(user({ mapDigest: { lastSentAt: daysAgo(14) } }), now)).toBeNull();
  // Thursday 10 ET → Saturday 10 ET: wait a week
  expect(digestSkipReason(user({ followSuggestionEmail: { lastSentAt: daysAgo(2) } }), now)).toBe('other_email_recently');
  // Wednesday's letter, even sent late at night in Hawaii, is over two days back: fine
  expect(digestSkipReason(user({ lastWeeklySummary: daysAgo(2.25) }), now)).toBeNull();
  expect(digestSkipReason(user({ lastWeeklySummary: daysAgo(3) }), now)).toBeNull();
  expect(digestSkipReason(user({ emailPreferences: { weeklyMapDigest: false } }), now)).toBe('opted_out');
  expect(digestSkipReason(user({ email: 'x@privaterelay.appleid.com' }), now)).toBe('no_usable_email');
  expect(digestSkipReason(user({ isTestAccount: true }), now)).toBe('internal');
});

test('the store report counts App Clip scans and signups, and a quiet month sends nothing', () => {
  const venue = { statsMonthly: { '2026-10': { scans: 5, clipScans: 14, clipSignups: 2, visits: 8 } } };
  expect(monthStats(venue, '2026-10')).toEqual({ scans: 19, signups: 2, saves: 0, visits: 8, redemptions: 0 });
  expect(hasActivity(monthStats(venue, '2026-10'))).toBe(true);
  expect(hasActivity(monthStats({ statsMonthly: { '2026-10': {} } }, '2026-10'))).toBe(false);
  expect(hasActivity(monthStats({}, '2026-10'))).toBe(false);
});
