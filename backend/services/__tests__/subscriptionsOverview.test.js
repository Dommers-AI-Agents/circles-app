jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../fridgeMail/shared', () => ({ SUBSCRIPTION_PRICE_CENTS: 799, SUB_ACTIVE: new Set(['active', 'trialing']) }));
const { appleEntry, fridgeEntry, listSubscriptions } = require('../subscriptionsOverview');

const NOW = Date.parse('2026-10-19T12:00:00Z');

test('Fridge Mail: price × grandparents, and whether it renews', () => {
  const plan = { recipients: [{ name: 'Linda Sgroi' }],
    subscription: { status: 'active', quantity: 1, currentPeriodEnd: '2026-11-19T01:01:11.000Z', cancelAtPeriodEnd: true } };
  expect(fridgeEntry(plan, NOW)).toMatchObject({ id: 'fridgemail', priceCents: 799, period: 'month', willRenew: false,
    periodEnd: '2026-11-19T01:01:11.000Z', billedBy: 'card', manage: 'fridgemail', what: expect.stringContaining('Linda Sgroi') });
  expect(fridgeEntry({ subscription: { status: 'active', quantity: 2 } }, NOW)).toMatchObject({ priceCents: 1598, quantity: 2, willRenew: true });
  expect(fridgeEntry({ subscription: { status: 'past_due', quantity: 1 } }, NOW).status).toBe('payment_issue');
  expect(fridgeEntry({ subscription: { status: 'canceled' } }, NOW)).toBeNull();
  expect(fridgeEntry({}, NOW)).toBeNull();
});

test('Apple: only live subscriptions, yearly vs monthly from the product', () => {
  expect(appleEntry({ id: 'premium', productId: 'com.favcircles.circles.premium.annual', status: 'active',
    expiry: '2026-11-10T00:00:00Z', now: NOW })).toMatchObject({ period: 'year', billedBy: 'apple', manage: 'appstore', willRenew: null });
  expect(appleEntry({ id: 'premium', productId: 'com.favcircles.circles.premium.subscription.monthly', status: 'grace_period',
    expiry: '2026-11-10T00:00:00Z', now: NOW })).toMatchObject({ period: 'month', status: 'payment_issue' });
  expect(appleEntry({ id: 'business', productId: 'x.business.subscription.monthly', status: 'expired', expiry: '2026-08-01T00:00:00Z', now: NOW })).toBeNull();
  expect(appleEntry({ id: 'premium', productId: 'p', status: 'active', expiry: '2026-01-01T00:00:00Z', now: NOW })).toBeNull();
  expect(appleEntry({ id: 'premium', productId: null, status: 'active', now: NOW })).toBeNull();
});

test('one list across both', async () => {
  const docs = {
    users: { subscriptionProductId: 'com.favcircles.circles.premium.annual', subscriptionStatus: 'active', subscriptionExpiryDate: '2026-11-10T00:00:00Z',
      ownerSubscriptionProductId: 'com.favcircles.circles.business.subscription.monthly', ownerSubscriptionStatus: 'expired' },
    fridgeMailPlans: { subscription: { status: 'active', quantity: 1 } }
  };
  const db = { collection: (name) => ({ doc: () => ({ get: async () => ({ exists: true, data: () => docs[name] }) }) }) };
  expect((await listSubscriptions('u1', { now: NOW, db })).map((s) => s.id)).toEqual(['premium', 'fridgemail']);
});
