// Per-user daily allowances (security audit 2026-10-01): the cap is real,
// all-or-nothing, per bucket and per UTC day, and env-tunable.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const dailyBudget = require('../dailyBudget');

beforeEach(() => {
  mockDb.rows('dailyBudgets').clear();
  delete process.env.EMAIL_DAILY_BUDGET;
  delete process.env.PLACES_LOOKUP_DAILY_BUDGET;
});

test('email budget allows 100 a day by default, then refuses', async () => {
  for (let i = 1; i <= 100; i++) {
    const r = await dailyBudget.consumeEmail('wes');
    expect(r).toEqual({ allowed: true, used: i, limit: 100 });
  }
  expect(await dailyBudget.consumeEmail('wes')).toEqual({ allowed: false, used: 100, limit: 100 });
  // Someone else's allowance is untouched
  expect((await dailyBudget.consumeEmail('britt')).allowed).toBe(true);
});

test('a multi-recipient spend is all-or-nothing', async () => {
  process.env.EMAIL_DAILY_BUDGET = '6';
  expect((await dailyBudget.consumeEmail('wes', 5)).allowed).toBe(true);
  // 5 used; 5 more doesn't fit, and nothing is spent by trying
  expect(await dailyBudget.consumeEmail('wes', 5)).toEqual({ allowed: false, used: 5, limit: 6 });
  expect(await dailyBudget.consumeEmail('wes', 1)).toEqual({ allowed: true, used: 6, limit: 6 });
});

test('buckets and days are counted separately', async () => {
  process.env.PLACES_LOOKUP_DAILY_BUDGET = '1';
  const day1 = new Date('2026-10-01T23:00:00Z');
  const day2 = new Date('2026-10-02T01:00:00Z');
  expect((await dailyBudget.consume('placesLookup', 'wes', 1, { now: day1 })).allowed).toBe(true);
  expect((await dailyBudget.consume('placesLookup', 'wes', 1, { now: day1 })).allowed).toBe(false);
  expect((await dailyBudget.consume('placesLookup', 'wes', 1, { now: day2 })).allowed).toBe(true);
  expect((await dailyBudget.consume('email', 'wes', 1, { now: day1 })).allowed).toBe(true);
  expect(mockDb.rows('dailyBudgets').get('placesLookup_wes_2026-10-01')).toMatchObject({ count: 1, bucket: 'placesLookup' });
});

test('no user id never spends', async () => {
  expect((await dailyBudget.consumeEmail(null)).allowed).toBe(false);
});

test('a Firestore failure fails open for email, closed for paid lookups', async () => {
  const original = mockDb.runTransaction;
  mockDb.runTransaction = async () => { throw new Error('unavailable'); };
  try {
    expect((await dailyBudget.consumeEmail('wes')).allowed).toBe(true);
    expect((await dailyBudget.consumePlacesLookup('wes')).allowed).toBe(false);
  } finally {
    mockDb.runTransaction = original;
  }
});
