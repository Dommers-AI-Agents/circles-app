// A customer's history at one store, for Get Rewards (2026-11-02)
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { summarize } = require('../rewardHistoryService');

test('totals visits, points earned and rewards used; newest first', () => {
  const events = [
    { type: 'redemption_refund', points: 100, offerTitle: 'Free coffee', createdAt: '2026-11-02T10:00:00Z' },
    { type: 'redemption', points: -100, status: 'expired', offerTitle: 'Free coffee', createdAt: '2026-11-02T09:00:00Z' },
    { type: 'redemption', points: -100, status: 'given', offerTitle: 'Free coffee', createdAt: '2026-11-01T09:00:00Z' },
    { type: 'venue_visit', points: 25, createdAt: '2026-10-31T09:00:00Z' },
    { type: 'venue_visit', points: 25, createdAt: '2026-10-30T09:00:00Z' },
    { type: 'sticker_save', points: 25, createdAt: '2026-10-29T09:00:00Z' },
    { type: 'something_else', points: 5, createdAt: '2026-10-28T09:00:00Z' }
  ];
  const s = summarize(events);
  expect(s).toMatchObject({ visits: 2, earned: 75, redeemed: 1, lastVisitAt: '2026-10-31T09:00:00Z', firstAt: '2026-10-28T09:00:00Z' });
  expect(s.recent.map((r) => [r.kind, r.points])).toEqual([
    ['refund', 100], ['expired', -100], ['redeem', -100], ['earn', 25], ['earn', 25], ['earn', 25]
  ]);
  expect(s.recent[0].title).toBe('Points back · Free coffee');
});

test('nothing yet: zeros and an empty list', () => {
  expect(summarize([])).toEqual({ visits: 0, earned: 0, redeemed: 0, firstAt: null, lastVisitAt: null, recent: [] });
});
