// Scheduling rules for the cards Wes writes from the backend: when a campaign
// is live, how often it comes back, and who sees it. Pure, so a Tuesday-only
// card can be tested on a Friday.
const {
  windowOpen, cadenceDue, audienceMatches, byPriority, toCard, compareVersions, bucket
} = require('../homeCards');

const NOON_UTC = Date.parse('2026-09-20T12:00:00Z');   // 08:00 New York
const DAY = 24 * 60 * 60 * 1000;
const NY = 'America/New_York';

describe('window', () => {
  test('a bare date means that day where the USER is', () => {
    // 2026-09-20T02:00Z is still the 19th in New York, so a card starting on
    // the 20th must not be live yet for them.
    const earlyUtc = Date.parse('2026-09-20T02:00:00Z');
    expect(windowOpen({ startsAt: '2026-09-20' }, earlyUtc, NY)).toBe(false);
    expect(windowOpen({ startsAt: '2026-09-20' }, NOON_UTC, NY)).toBe(true);
  });

  test('tomorrow is not today, and an ended card is over', () => {
    expect(windowOpen({ startsAt: '2026-09-21' }, NOON_UTC, NY)).toBe(false);
    expect(windowOpen({ endsAt: '2026-09-19' }, NOON_UTC, NY)).toBe(false);
    expect(windowOpen({ startsAt: '2026-09-19', endsAt: '2026-09-21' }, NOON_UTC, NY)).toBe(true);
  });

  test('a full timestamp is an absolute instant, and no window means always', () => {
    expect(windowOpen({ startsAt: '2026-09-20T13:00:00Z' }, NOON_UTC, NY)).toBe(false);
    expect(windowOpen({ startsAt: '2026-09-20T11:00:00Z' }, NOON_UTC, NY)).toBe(true);
    expect(windowOpen({}, NOON_UTC, NY)).toBe(true);
  });

  test('an unparseable date is ignored rather than muting the card', () => {
    expect(windowOpen({ startsAt: 'whenever' }, NOON_UTC, NY)).toBe(true);
  });
});

describe('cadence', () => {
  test('never acked is always due', () => {
    expect(cadenceDue({ repeatDays: 0 }, null, NOON_UTC)).toBe(true);
  });

  test('repeatDays 0 means once ever', () => {
    const ack = { action: 'skipped', at: new Date(NOON_UTC - 400 * DAY).toISOString() };
    expect(cadenceDue({ repeatDays: 0 }, ack, NOON_UTC)).toBe(false);
    expect(cadenceDue({}, ack, NOON_UTC)).toBe(false);
  });

  test('a weekly card comes back on day seven, not day six', () => {
    const six = { at: new Date(NOON_UTC - 6 * DAY).toISOString() };
    const seven = { at: new Date(NOON_UTC - 7 * DAY).toISOString() };
    expect(cadenceDue({ repeatDays: 7 }, six, NOON_UTC)).toBe(false);
    expect(cadenceDue({ repeatDays: 7 }, seven, NOON_UTC)).toBe(true);
  });
});

describe('audience', () => {
  const user = (extra = {}) => ({ id: 'u1', createdAt: new Date(NOON_UTC - 30 * DAY).toISOString(), ...extra });
  const ctx = { now: NOON_UTC, appVersion: '1.3.3' };

  test('no audience means everyone', () => {
    expect(audienceMatches({ id: 'c' }, user(), ctx)).toBe(true);
  });

  test('premium either way', () => {
    const card = { id: 'c', audience: { premium: true } };
    expect(audienceMatches(card, user(), ctx)).toBe(false);
    expect(audienceMatches(card, user({ isPremium: true }), ctx)).toBe(true);
    expect(audienceMatches(card, user({ subscriptionStatus: 'active' }), ctx)).toBe(true);
    const free = { id: 'c', audience: { premium: false } };
    expect(audienceMatches(free, user({ isPremium: true }), ctx)).toBe(false);
  });

  test('a card about a new feature can require the build that has it', () => {
    const card = { id: 'c', audience: { minAppVersion: '1.3.3' } };
    expect(audienceMatches(card, user(), { ...ctx, appVersion: '1.3.2' })).toBe(false);
    expect(audienceMatches(card, user(), { ...ctx, appVersion: '1.3.3' })).toBe(true);
    expect(audienceMatches(card, user(), { ...ctx, appVersion: '1.4.0' })).toBe(true);
    // An old build that sends no version is not excluded on a guess.
    expect(audienceMatches(card, user(), { ...ctx, appVersion: null })).toBe(true);
  });

  test('account age, both directions', () => {
    expect(audienceMatches({ id: 'c', audience: { newerThanDays: 7 } }, user(), ctx)).toBe(false);
    expect(audienceMatches({ id: 'c', audience: { newerThanDays: 90 } }, user(), ctx)).toBe(true);
    expect(audienceMatches({ id: 'c', audience: { olderThanDays: 7 } }, user(), ctx)).toBe(true);
    expect(audienceMatches({ id: 'c', audience: { olderThanDays: 90 } }, user(), ctx)).toBe(false);
  });

  test('a percentage rollout is stable per user, not per app open', () => {
    const card = { id: 'launch', audience: { percent: 50 } };
    const first = audienceMatches(card, user(), ctx);
    for (let i = 0; i < 5; i++) expect(audienceMatches(card, user(), ctx)).toBe(first);
    // and it actually splits the population
    const ids = Array.from({ length: 200 }, (_, i) => `user${i}`);
    const inCohort = ids.filter(id => audienceMatches(card, user({ id }), ctx)).length;
    expect(inCohort).toBeGreaterThan(60);
    expect(inCohort).toBeLessThan(140);
    // 100% is everyone
    expect(audienceMatches({ id: 'x', audience: { percent: 100 } }, user(), ctx)).toBe(true);
  });
});

describe('shape and order', () => {
  test('higher priority wins; a later start breaks a tie', () => {
    const cards = [
      { id: 'a', priority: 1, startsAt: '2026-09-01' },
      { id: 'b', priority: 9, startsAt: '2026-09-01' },
      { id: 'c', priority: 1, startsAt: '2026-09-18' }
    ].sort(byPriority);
    expect(cards.map(c => c.id)).toEqual(['b', 'c', 'a']);
  });

  test('defaults: overlay, Show me / Skip, and a key that carries the memory', () => {
    const card = toCard({ id: 'widget-launch', title: 'New widget' });
    expect(card).toMatchObject({
      key: 'card:widget-launch',
      type: 'custom',
      actionLabel: 'Show me',
      skipLabel: 'Skip',
      presentation: 'overlay',
      override: false,
      bypassInterval: false
    });
    expect(toCard({ id: 'x', title: 't', presentation: 'inline' }).presentation).toBe('inline');
  });
});

test('version compare handles ragged lengths', () => {
  expect(compareVersions('1.3', '1.3.0')).toBe(0);
  expect(compareVersions('1.10.0', '1.9.0')).toBe(1);
  expect(bucket('u1', 'c1')).toBe(bucket('u1', 'c1'));
});
