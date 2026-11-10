// Insights: the fold's rules (customers, busiest times, offers, score,
// comments awaiting a reply) and the hour-long cache with stale answers.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore();
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: MockFieldValue,
  admin: { firestore: { FieldValue: MockFieldValue } }
}));
const mockListCustomers = jest.fn(async () => []);
jest.mock('../storeCustomers', () => ({ listCustomers: (...args) => mockListCustomers(...args) }));
jest.mock('../venueHelpers', () => ({
  venueGlobalPlaceId: async (venue) => venue.globalPlaceId || null,
  venueManagerIds: (venue) => venue.managerUserIds || []
}));

const insights = require('../venueInsights');

const NOW = new Date('2026-11-09T18:00:00.000Z');
const daysAgo = (n, hour = 12) => new Date(NOW.getTime() - n * 86400000 - (12 - hour) * 3600000).toISOString();
const visit = (userId, n, hour) => ({ type: 'venue_visit', userId, createdAt: daysAgo(n, hour) });
const redemption = (userId, offerId, offerTitle, n = 1) => ({ type: 'redemption', userId, offerId, offerTitle, createdAt: daysAgo(n) });
const customer = (id, purchases, lastDaysAgo, removed = false) => ({
  user: { id }, purchases, lastScanAt: lastDaysAgo === null ? null : daysAgo(lastDaysAgo), removed, points: 0, rewardsClaimed: 0
});
const base = { range: '30d', since: new Date(NOW.getTime() - 30 * 86400000), now: NOW, timeZone: 'America/New_York' };

describe('computeInsights', () => {
  it('splits the period\'s visitors into new and returning, and measures repeat, regulars and lapsed all-time', () => {
    const data = insights.computeInsights({
      ...base,
      events: [visit('ana', 2), visit('ana', 9), visit('ben', 3), visit('cy', 1)],
      customers: [
        customer('ana', 2, 2),       // both purchases this period: new
        customer('ben', 5, 3),       // long-time regular
        customer('cy', 1, 1),        // first purchase: new
        customer('dee', 4, 45),      // regular who hasn't been back in 45 days
        customer('eve', 3, 10, true) // removed from rewards: ignored
      ]
    });
    expect(data.customers).toEqual({
      visits: 4, visitors: 3, newCustomers: 2, returningCustomers: 1,
      total: 4, repeatRatePct: 75, regulars: 2, lapsed: 1, referred: 0
    });
  });

  it('counts busiest hours and days in the store\'s own time zone', () => {
    // 2026-11-09 is a Monday; 18:00Z is 1pm in New York
    const data = insights.computeInsights({
      ...base,
      events: [
        { type: 'venue_visit', userId: 'a', createdAt: '2026-11-09T18:00:00.000Z' },
        { type: 'venue_visit', userId: 'b', createdAt: '2026-11-09T18:30:00.000Z' },
        { type: 'venue_visit', userId: 'c', createdAt: '2026-11-08T23:30:00.000Z' } // Sunday 6:30pm NY
      ]
    });
    expect(data.busiest.hours[13]).toBe(2);
    expect(data.busiest.hours[18]).toBe(1);
    expect(data.busiest.days[1]).toBe(2); // Monday
    expect(data.busiest.days[0]).toBe(1); // Sunday
  });

  it('ranks offers by redemptions and leaves cancelled ones out', () => {
    const data = insights.computeInsights({
      ...base,
      events: [
        redemption('a', 'o1', 'Free coffee'), redemption('b', 'o1', 'Free coffee'),
        redemption('c', 'o2', 'Half-price bagel'),
        { ...redemption('d', 'o2', 'Half-price bagel'), status: 'cancelled' }
      ]
    });
    expect(data.redemptions).toBe(3);
    expect(data.offers).toEqual([
      { offerId: 'o1', title: 'Free coffee', redemptions: 2 },
      { offerId: 'o2', title: 'Half-price bagel', redemptions: 1 }
    ]);
  });

  it('scores the store from its savers\' 0–10 ratings, with the trend against the 30 days before', () => {
    const data = insights.computeInsights({
      ...base,
      saves: [
        { addedBy: 'a', userRating: 9, userRatedAt: daysAgo(3) },
        { addedBy: 'b', userRating: 8, userRatedAt: daysAgo(10) },
        { addedBy: 'c', userRating: 4, userRatedAt: daysAgo(40) },
        { addedBy: 'd', userRating: 6, userRatedAt: daysAgo(50) },
        { addedBy: 'e' }, // saved, never rated
        { addedBy: 'a' }  // a second save by the same person: one saver
      ],
      google: { rating: 4.6, userRatingsTotal: 212 }
    });
    expect(data.score.average).toBe(6.8);
    expect(data.score.ratings).toBe(4);
    expect(data.score.recommend).toBe(2);
    expect(data.score.recommendPct).toBe(50);
    expect(data.score.trend).toBe(3.5); // 8.5 now vs 5 before
    expect(data.score.recent.map((r) => r.rating)).toEqual([9, 8, 4, 6]);
    expect(data.score.google).toEqual({ rating: 4.6, total: 212 });
    expect(data.saves).toBe(5);
  });

  it('has no score, trend or Google rating when there is nothing to average', () => {
    const data = insights.computeInsights({ ...base, saves: [{ addedBy: 'a' }] });
    expect(data.score).toEqual({ average: null, ratings: 0, recommend: 0, recommendPct: null, trend: null, recent: [], google: null });
    expect(data.customers.repeatRatePct).toBeNull();
  });

  it('lists comments nobody on the team has answered, newest first, skipping the team\'s own and hidden ones', () => {
    const data = insights.computeInsights({
      ...base,
      teamIds: ['owner', 'mgr'],
      comments: [
        { id: 'c1', userId: 'ana', text: 'Great patio', createdAt: daysAgo(2) },
        { id: 'c2', userId: 'ben', text: 'Slow on Sundays', createdAt: daysAgo(5) },
        { id: 'r1', userId: 'mgr', parentCommentId: 'c2', createdAt: daysAgo(4) },
        { id: 'c3', userId: 'owner', text: 'Thanks all', createdAt: daysAgo(1) },
        { id: 'c4', userId: 'cy', text: 'Cold fries', createdAt: daysAgo(40) },
        { id: 'r2', userId: 'dee', parentCommentId: 'c4', createdAt: daysAgo(39) }, // another customer, not the team
        { id: 'c5', userId: 'eve', text: 'spam', createdAt: daysAgo(1), moderationStatus: 'removed' }
      ]
    });
    expect(data.comments.total).toBe(4);
    expect(data.comments.inPeriod).toBe(3);
    expect(data.comments.awaitingReply).toBe(2);
    expect(data.comments.awaiting.map((c) => c.id)).toEqual(['c1', 'c4']);
  });

  it('refuses a range it does not know', () => {
    expect(() => insights.parseRange('7d')).toThrow(/30d, 90d or 12m/);
    expect(insights.parseRange(undefined)).toBe('30d');
  });
});

describe('getInsights cache', () => {
  const venue = { venueId: 'v1', venueName: 'Sal\'s', ownerUserId: 'owner', globalPlaceId: 'gp1' };

  beforeEach(async () => {
    mockListCustomers.mockClear();
    mockListCustomers.mockResolvedValue([customer('ana', 2, 2)]);
    await mockDb.collection('stickerVenues').doc('v1').set({ venueName: 'Sal\'s' });
    await mockDb.collection('rewardEvents').doc('e1').set({ venueId: 'v1', ...visit('ana', 2) });
    await mockDb.collection('globalPlaces').doc('gp1').set({ followersCount: 7, googleData: { rating: 4.4, userRatingsTotal: 50 } });
    await mockDb.collection('places').doc('p1').set({ globalPlaceId: 'gp1', deletedAt: null, addedBy: 'ana', userRating: 9, userRatedAt: daysAgo(1) });
  });

  it('computes, stores on the venue, and answers from the cache while it is fresh', async () => {
    const first = await insights.getInsights(venue, '30d', NOW);
    expect(first.stale).toBe(false);
    expect(first.customers.visits).toBe(1);
    expect(first.score.average).toBe(9);
    expect(first.followers).toBe(7);
    const stored = (await mockDb.collection('stickerVenues').doc('v1').get()).data();
    expect(stored.insightsCache['30d'].data.customers.visits).toBe(1);

    const again = await insights.getInsights({ ...venue, insightsCache: stored.insightsCache }, '30d', new Date(NOW.getTime() + 10 * 60000));
    expect(again.stale).toBe(false);
    expect(mockListCustomers).toHaveBeenCalledTimes(1);
  });

  it('answers a stale cache at once and refreshes behind it', async () => {
    const old = { at: new Date(NOW.getTime() - 3 * 3600000).toISOString(), data: { customers: { visits: 99 }, computedAt: 'x' } };
    const result = await insights.getInsights({ ...venue, insightsCache: { '30d': old } }, '30d', NOW);
    expect(result.stale).toBe(true);
    expect(result.customers.visits).toBe(99);
    await new Promise((resolve) => setTimeout(resolve, 20));
    const stored = (await mockDb.collection('stickerVenues').doc('v1').get()).data();
    expect(stored.insightsCache['30d'].data.customers.visits).toBe(1);
  });
});
