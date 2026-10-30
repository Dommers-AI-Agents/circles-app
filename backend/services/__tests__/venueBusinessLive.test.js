// Order ahead is for stores whose owner pays for Business; a comp doesn't
// count (Wes, 2026-10-21: "There should be no comped stores").
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { isVenueBusinessLive, isVenueLoyaltyActive, registerScanEarns, loyaltyNeverStarted } = require('../ownerSubscriptionService');

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

// The register code is the owner demo at a store nobody has claimed yet
// (Wes, 2026-10-29); a lapsed owner's store stays paused.
// No points until the store's rewards are live, claimed or not (Wes,
// 2026-10-30): an unclaimed store no longer pays them as an owner demo.
test('a register scan earns only where loyalty is live: not at an unclaimed store, never at a lapsed one', async () => {
  await mockDb.collection('users').doc('lapsed').set({ ownerSubscriptionStatus: 'expired' });
  expect(await registerScanEarns({ venueId: 'v3' })).toMatchObject({ earns: false, demo: false });
  // A super-user's demo switch runs the store like a subscriber's until it ends
  const later = new Date(Date.now() + 3600 * 1000).toISOString();
  const ended = new Date(Date.now() - 3600 * 1000).toISOString();
  expect(await registerScanEarns({ venueId: 'v6', loyaltyDemoUntil: later })).toMatchObject({ earns: true, demo: false });
  expect(await registerScanEarns({ venueId: 'v7', loyaltyDemoUntil: ended })).toMatchObject({ earns: false });
  expect(await registerScanEarns({ venueId: 'v4', ownerUserId: 'lapsed' })).toMatchObject({ earns: false, demo: false });
  expect(await registerScanEarns({ venueId: 'v5', ownerUserId: 'lapsed', loyaltyComped: true })).toMatchObject({ earns: true, demo: false });
});

test('a claimed store that never subscribed has not started; one whose plan ran out is paused', async () => {
  await mockDb.collection('users').doc('never').set({ displayName: 'Claimed, never paid' });
  await mockDb.collection('users').doc('ranout').set({ ownerSubscriptionStatus: 'expired', ownerSubscriptionExpiryDate: '2026-01-01T00:00:00.000Z' });
  expect(await loyaltyNeverStarted({ venueId: 'a', ownerUserId: 'never' })).toBe(true);
  expect(await loyaltyNeverStarted({ venueId: 'b', ownerUserId: 'ranout' })).toBe(false);
  expect(await loyaltyNeverStarted({ venueId: 'c', ownerUserId: 'never', loyaltyComped: true })).toBe(false);
});
