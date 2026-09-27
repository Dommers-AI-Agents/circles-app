// Tests for the advisor's spend controls. Firestore and the subscription
// lookup are both mocked — what's under test is the decision logic that stands
// between a tap and a paid API call.

const mockUserDocs = new Map();
let mockSubscriptionStatus = 'active';

jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({
      doc: (id) => ({
        __id: id,
        get: async () => ({
          exists: mockUserDocs.has(id),
          data: () => mockUserDocs.get(id)
        })
      })
    }),
    runTransaction: async (fn) =>
      fn({
        get: async (ref) => ({ exists: mockUserDocs.has(ref.__id), data: () => mockUserDocs.get(ref.__id) }),
        set: (ref, value) => mockUserDocs.set(ref.__id, { ...(mockUserDocs.get(ref.__id) || {}), ...value })
      })
  })
}));

jest.mock('../subscriptionLimitService', () => ({
  getUserSubscriptionData: async () => ({ subscriptionStatus: mockSubscriptionStatus })
}));

const quota = require('../circleAdvisorQuota');

const circles = [
  { id: 'c1', name: 'Charlotte', placesCount: 40, topCategories: ['restaurant'], topCities: ['Charlotte'] },
  { id: 'c2', name: 'Pizza', placesCount: 10, topCategories: ['restaurant'], topCities: ['Belmar'] }
];

const today = () => new Date().toISOString().slice(0, 10);

beforeEach(() => {
  mockUserDocs.clear();
  mockSubscriptionStatus = 'active';
});

describe('premium gate', () => {
  it.each(['active', 'trial'])('allows a %s subscriber', async (status) => {
    mockSubscriptionStatus = status;
    const gate = await quota.check('u1', circles);
    expect(gate.allowed).toBe(true);
  });

  it.each(['none', 'expired'])('blocks a %s account with premium_required', async (status) => {
    mockSubscriptionStatus = status;
    const gate = await quota.check('u1', circles);
    expect(gate).toEqual({ allowed: false, reason: 'premium_required' });
  });

  it('checks the subscription before anything else, so a free account never reaches the counters', async () => {
    mockSubscriptionStatus = 'none';
    mockUserDocs.set('u1', { runTimes: [new Date().toISOString(), new Date().toISOString()] });
    const gate = await quota.check('u1', circles);
    // Would have been a limit error if the counters were consulted first.
    expect(gate.reason).toBe('premium_required');
  });
});

describe('per-user weekly limit', () => {
  const daysAgo = (n) => new Date(Date.now() - n * 24 * 60 * 60 * 1000).toISOString();

  it('allows a run below the limit and reports what remains', async () => {
    mockUserDocs.set('u1', { runTimes: [daysAgo(3)] });
    const gate = await quota.check('u1', circles);
    expect(gate.allowed).toBe(true);
    expect(gate.remaining).toBe(quota.PER_USER_WEEKLY - 2);
  });

  it('blocks once the week is spent and says when the next run frees up', async () => {
    mockUserDocs.set('u1', { runTimes: [daysAgo(1), daysAgo(5)] });
    const gate = await quota.check('u1', circles);
    expect(gate.allowed).toBe(false);
    expect(gate.reason).toBe('user_weekly_limit');
    expect(gate.limit).toBe(quota.PER_USER_WEEKLY);
    // The run from 5 days ago ages out in 2 days.
    const inDays = (new Date(gate.nextAvailableAt) - Date.now()) / (24 * 60 * 60 * 1000);
    expect(inDays).toBeCloseTo(2, 1);
  });

  it('ignores runs older than a week', async () => {
    mockUserDocs.set('u1', { runTimes: [daysAgo(8), daysAgo(9), daysAgo(10)] });
    expect((await quota.check('u1', circles)).allowed).toBe(true);
  });

  it('defaults to 2 runs a week', () => {
    expect(quota.PER_USER_WEEKLY).toBe(2);
  });

  it('record() keeps only this week\'s runs plus the new one', async () => {
    mockUserDocs.set('u1', { runTimes: [daysAgo(9), daysAgo(2)] });
    await quota.record('u1', 'key', { schemes: [], merges: [] }, 3.5);
    const doc = mockUserDocs.get('u1');
    expect(doc.runTimes).toHaveLength(2);
    // The 9-day-old run is gone; the 2-day-old one and the new one remain.
    expect(Date.now() - new Date(doc.runTimes[0])).toBeGreaterThan(1.9 * 24 * 60 * 60 * 1000);
    expect(Date.now() - new Date(doc.runTimes[1])).toBeLessThan(60 * 1000);
    expect((await quota.check('u1', circles)).reason).toBe('user_weekly_limit');
  });
});

describe('global daily limit', () => {
  it('blocks everyone once the global cap is hit', async () => {
    mockUserDocs.set('__global', { date: today(), count: quota.GLOBAL_DAILY });
    const gate = await quota.check('u1', circles);
    expect(gate.allowed).toBe(false);
    expect(gate.reason).toBe('global_daily_limit');
  });

  it("ignores yesterday's global count", async () => {
    mockUserDocs.set('__global', { date: '2020-01-01', count: 99999 });
    expect((await quota.check('u1', circles)).allowed).toBe(true);
  });
});

describe('result cache', () => {
  const cached = { schemes: [{ circleId: 'c1', scheme: 'place', confidence: 1 }], merges: [] };

  it('serves an unchanged circle set from cache', async () => {
    mockUserDocs.set('u1', {
      date: today(),
      count: 1,
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached,
      cachedAt: new Date().toISOString()
    });

    const gate = await quota.check('u1', circles);
    expect(gate.allowed).toBe(true);
    expect(gate.cached).toEqual(cached);
  });

  it('serves from cache even when the weekly limit is spent — re-opening is not rationed', async () => {
    mockUserDocs.set('u1', {
      runTimes: [new Date().toISOString(), new Date().toISOString()],
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached,
      cachedAt: new Date().toISOString()
    });

    const gate = await quota.check('u1', circles);
    expect(gate.cached).toEqual(cached);
  });

  it('misses when a circle was renamed', async () => {
    mockUserDocs.set('u1', {
      date: today(), count: 1,
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached, cachedAt: new Date().toISOString()
    });

    const renamed = [{ ...circles[0], name: 'Charlotte NC' }, circles[1]];
    const gate = await quota.check('u1', renamed);
    expect(gate.cached).toBeUndefined();
    expect(gate.cacheKey).toBeDefined();
  });

  it('misses when a place was added to a circle', async () => {
    mockUserDocs.set('u1', {
      date: today(), count: 1,
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached, cachedAt: new Date().toISOString()
    });

    const grown = [{ ...circles[0], placesCount: 41 }, circles[1]];
    expect((await quota.check('u1', grown)).cached).toBeUndefined();
  });

  it('still serves a 6-day-old answer — two runs a week must not be spent on unchanged circles', async () => {
    mockUserDocs.set('u1', {
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached,
      cachedAt: new Date(Date.now() - 6 * 24 * 60 * 60 * 1000).toISOString()
    });
    expect((await quota.check('u1', circles)).cached).toEqual(cached);
  });

  it('misses once the entry is older than its TTL', async () => {
    mockUserDocs.set('u1', {
      date: today(), count: 1,
      cacheKey: quota.fingerprint(circles),
      cachedResult: cached,
      cachedAt: new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString()
    });
    expect((await quota.check('u1', circles)).cached).toBeUndefined();
  });
});

describe('fingerprint', () => {
  it('is order-independent — the same circles listed differently is the same set', () => {
    expect(quota.fingerprint(circles)).toBe(quota.fingerprint([...circles].reverse()));
  });

  it('changes when a circle is added', () => {
    const more = [...circles, { id: 'c3', name: 'New', placesCount: 1 }];
    expect(quota.fingerprint(more)).not.toBe(quota.fingerprint(circles));
  });

  it('changes when a circle is removed', () => {
    expect(quota.fingerprint([circles[0]])).not.toBe(quota.fingerprint(circles));
  });
});
