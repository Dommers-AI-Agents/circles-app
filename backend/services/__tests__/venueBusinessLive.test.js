// Order ahead is for stores whose owner pays for Business; a comp doesn't
// count (Wes, 2026-10-21: "There should be no comped stores").
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { isVenueBusinessLive, isVenueLoyaltyActive } = require('../ownerSubscriptionService');

const future = new Date(Date.now() + 30 * 86400000).toISOString();

beforeEach(() => mockDb.rows('users').clear());

test('a comped store with a free owner: loyalty runs, ordering does not', async () => {
  await mockDb.collection('users').doc('free').set({ displayName: 'Free owner' });
  const venue = { venueId: 'v1', ownerUserId: 'free', loyaltyComped: true };
  expect(await isVenueLoyaltyActive(venue)).toBe(true);
  expect(await isVenueBusinessLive(venue)).toBe(false);
});

test('an owner paying for Business for this store: ordering is live', async () => {
  await mockDb.collection('users').doc('paid').set({
    ownerSubscriptionStatus: 'active', ownerSubscriptionExpiryDate: future, ownerSubscriptionVenueId: 'v2',
    subscriptionStatus: 'active', ownerSubscriptionProductId: 'com.favcircles.circles.business.monthly'
  });
  const live = await isVenueBusinessLive({ venueId: 'v2', ownerUserId: 'paid' });
  const other = await isVenueBusinessLive({ venueId: 'elsewhere', ownerUserId: 'paid' });
  expect(other).toBe(false);
  expect(live).toBe(true);
});

test('no owner, no orders', async () => {
  expect(await isVenueBusinessLive({ venueId: 'v3' })).toBe(false);
});
