// Bring a friend: who gets remembered, who gets paid when, and the guards.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: MockFieldValue, admin: { firestore: { FieldValue: MockFieldValue } } }));
const mockPush = jest.fn();
jest.mock('../notifyQuiet', () => ({ sendInBackground: (...a) => mockPush(...a) }));
jest.mock('../venueHelpers', () => ({ venueGlobalPlaceId: async () => 'gp1' }));
const awards = [];
jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  awardPoints: async (args) => {
    if (awards.some((a) => a.idempotencyKey === args.idempotencyKey)) return { awarded: false, duplicate: true };
    awards.push(args); return { awarded: true, points: args.points };
  }
}));

const ref = require('../storeReferrals');
const NOW = new Date('2026-11-09T18:00:00.000Z');
const venue = { venueId: 'v1', venueName: "Sal's", windowCode: 'WIN123', referrals: { enabled: true, referrerPoints: 50, friendPoints: 25 } };

beforeEach(async () => {
  awards.length = 0; mockPush.mockClear();
  mockDb.rows('users').clear(); mockDb.rows('rewardEvents').clear();
  await mockDb.collection('users').doc('ana').set({ firstName: 'Ana', rewardPointsByVenue: { v1: { points: 100, purchases: 4 } } });
  await mockDb.collection('users').doc('ben').set({ firstName: 'Ben' });
});

test('settings, the public offer and the invite link', () => {
  expect(ref.settingsOf({})).toEqual({ enabled: false, referrerPoints: 50, friendPoints: 25, couponId: null });
  expect(ref.normalizeSettings({ enabled: true, referrerPoints: 100, friendPoints: 10 })).toEqual({ enabled: true, referrerPoints: 100, friendPoints: 10, couponId: null });
  expect(() => ref.normalizeSettings({ referrerPoints: 99999 })).toThrow(/whole number/);
  expect(ref.inviteUrl(venue, 'ana')).toBe('https://api.favcircles.com/s/WIN123?ref=ana');
  expect(ref.publicReferral(venue, 'ana', { live: true })).toEqual({ enabled: true, referrerPoints: 50, friendPoints: 25, inviteUrl: 'https://api.favcircles.com/s/WIN123?ref=ana', friendCoupon: null });
  expect(ref.publicReferral(venue, 'ana', { live: false })).toBeNull();
});

test('a coupon for the friend rides on the invite link while the store still offers it (2026-11-14)', () => {
  const mailer = { couponId: 'ABCDEF', title: '20% off any pickup order', expiresAt: new Date(NOW.getTime() + 20 * 86400000).toISOString(), active: true };
  const withCoupon = { ...venue, coupons: [mailer], referrals: { ...venue.referrals, couponId: 'ABCDEF' } };
  expect(ref.inviteUrl(withCoupon, 'ana', { now: NOW })).toBe('https://api.favcircles.com/s/WIN123?ref=ana&c=ABCDEF');
  expect(ref.publicReferral(withCoupon, 'ana', { live: true, now: NOW }).friendCoupon).toMatchObject({ couponId: 'ABCDEF', title: '20% off any pickup order' });
  const ended = { ...withCoupon, coupons: [{ ...mailer, expiresAt: new Date(NOW.getTime() - 86400000).toISOString() }] };
  expect(ref.inviteUrl(ended, 'ana', { now: NOW })).toBe('https://api.favcircles.com/s/WIN123?ref=ana');
  expect(ref.normalizeSettings({ enabled: true, couponId: 'abcdef' }).couponId).toBe('ABCDEF');
  expect(() => ref.normalizeSettings({ couponId: 'bad!' })).toThrow(/one of your coupons/);
});

test('a friend is remembered once, never yourself, never an existing customer', async () => {
  const settings = ref.settingsOf(venue);
  expect(ref.shouldRemember({ settings, live: true, refUserId: 'ana', newUserId: 'ben', bucket: null })).toBe(true);
  expect(ref.shouldRemember({ settings, live: true, refUserId: 'ana', newUserId: 'ana', bucket: null })).toBe(false);
  expect(ref.shouldRemember({ settings, live: true, refUserId: 'ana', newUserId: 'ben', bucket: { purchases: 2 } })).toBe(false);
  expect(ref.shouldRemember({ settings, live: true, refUserId: 'ana', newUserId: 'ben', bucket: { referredBy: 'cy' } })).toBe(false);
  expect(ref.shouldRemember({ settings, live: false, refUserId: 'ana', newUserId: 'ben', bucket: null })).toBe(false);

  expect(await ref.remember({ venue, refUserId: 'ana', newUserId: 'ben', live: true, now: NOW })).toEqual({ remembered: true });
  expect((await mockDb.collection('users').doc('ben').get()).data().rewardPointsByVenue.v1.referredBy).toBe('ana');
  expect(await ref.remember({ venue, refUserId: 'nobody', newUserId: 'cy', live: true })).toEqual({ remembered: false });
});

test('the first purchase pays both once; the referrer is capped at 20 a month', async () => {
  const before = { referredBy: 'ana', purchases: 0 };
  const paid = await ref.creditOnVisit({ venue, friendUserId: 'ben', bucketBefore: before, now: NOW });
  expect(paid).toMatchObject({ credited: true, referrerPoints: 50, friendPoints: 25, refUserId: 'ana' });
  expect(awards.map((a) => [a.userId, a.role, a.points, a.sourceUserId])).toEqual([['ben', 'friend', 25, 'ana'], ['ana', 'referrer', 50, 'ben']]);
  expect(awards[1].bucketUpdate['referralsByMonth.2026-11']).toEqual({ __increment: 1 });
  expect(mockPush).toHaveBeenCalledTimes(2);
  expect(mockPush.mock.calls[0][1].title).toBe("Ben made their first visit to Sal's");

  expect(await ref.creditOnVisit({ venue, friendUserId: 'ben', bucketBefore: before, now: NOW })).toEqual({ credited: false, reason: 'duplicate' });
  expect(await ref.creditOnVisit({ venue, friendUserId: 'cy', bucketBefore: { referredBy: 'ana', purchases: 1 }, now: NOW })).toEqual({ credited: false, reason: 'not_first' });
  expect(await ref.creditOnVisit({ venue, friendUserId: 'dee', bucketBefore: {}, now: NOW })).toEqual({ credited: false, reason: 'not_first' });
  expect(await ref.creditOnVisit({ venue: { ...venue, referrals: { enabled: false } }, friendUserId: 'dee', bucketBefore: before, now: NOW })).toEqual({ credited: false, reason: 'off' });

  await mockDb.collection('users').doc('ana').update('rewardPointsByVenue.v1.referralsByMonth', { '2026-11': 20 });
  expect(await ref.creditOnVisit({ venue, friendUserId: 'eve', bucketBefore: { referredBy: 'ana', purchases: 0 }, now: NOW })).toEqual({ credited: false, reason: 'capped' });
});

test('the owner sees how many friends were brought in', async () => {
  await mockDb.collection('rewardEvents').doc('e1').set({ venueId: 'v1', type: 'referral', role: 'referrer', points: 50, createdAt: '2026-11-02T00:00:00.000Z' });
  await mockDb.collection('rewardEvents').doc('e2').set({ venueId: 'v1', type: 'referral', role: 'friend', points: 25, createdAt: '2026-11-02T00:00:00.000Z' });
  await mockDb.collection('rewardEvents').doc('e3').set({ venueId: 'v1', type: 'referral', role: 'referrer', points: 50, createdAt: '2026-09-02T00:00:00.000Z' });
  const stats = await ref.stats(venue);
  expect(stats.friendsBrought).toBe(2);
  expect(stats.pointsPaid).toBe(125);
});
