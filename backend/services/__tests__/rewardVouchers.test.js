// Reward tickets (2026-11-01): staff tap "Given" on the customer's phone; a
// ticket that runs out unclaimed expires and its points come back.
const { FakeFirestore, FakeFieldValue: mockFieldValue } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: mockFieldValue }));
jest.mock('../rewardService', () => ({ incrementVenueStats: jest.fn(), walletBalanceChanged: jest.fn() }));
const svc = require('../rewardVoucherService');

const MIN = 60 * 1000;
const t0 = Date.parse('2026-11-01T18:00:00Z');

function issue(id, { userId = 'cust', minutes = 15, at = t0 } = {}) {
  const voucher = svc.newVoucher({
    voucherId: id, userId, venueId: 'v1', venueName: 'Sal’s Bakery',
    offer: { offerId: 'o1', title: 'Free drip coffee', pointsCost: 100 },
    voucherCode: 'AB12', expiresAt: new Date(at + minutes * MIN).toISOString(), now: new Date(at)
  });
  mockDb.collection('rewardVouchers').doc(id).set(voucher);
  mockDb.collection('rewardEvents').doc(id).set({ type: 'redemption', status: 'issued' });
  mockDb.collection('users').doc(userId).set({ rewardPoints: 0, 'rewardPointsByVenue.v1.points': 0 });
}

beforeEach(() => {
  for (const name of ['rewardVouchers', 'rewardEvents', 'users']) mockDb.rows(name).clear();
});

test('staff tap Given: the ticket is given, once', async () => {
  issue('r1');
  const given = await svc.markGiven('cust', 'r1', t0 + 5 * MIN);
  expect(given).toMatchObject({ status: 'given', refunded: false });
  expect(mockDb.rows('rewardEvents').get('r1').status).toBe('given');
  await expect(svc.markGiven('cust', 'r1', t0 + 6 * MIN)).resolves.toMatchObject({ status: 'given' });
});

test('someone else’s ticket is not theirs to mark', async () => {
  issue('r1');
  await expect(svc.markGiven('stranger', 'r1', t0)).rejects.toMatchObject({ status: 404 });
});

test('a slow handover just after the countdown still counts; well after, it doesn’t', async () => {
  issue('r1');
  await expect(svc.markGiven('cust', 'r1', t0 + 16 * MIN)).resolves.toMatchObject({ status: 'given' });
  issue('r2');
  await expect(svc.markGiven('cust', 'r2', t0 + 20 * MIN)).rejects.toMatchObject({ code: 'VOUCHER_EXPIRED' });
});

test('an unclaimed ticket expires and its points come back, once', async () => {
  issue('r1');
  expect(await svc.expireOne('r1', t0 + 10 * MIN)).toBe(false); // still open
  expect(await svc.expireOne('r1', t0 + 20 * MIN)).toBe(true);
  expect(await svc.expireOne('r1', t0 + 21 * MIN)).toBe(false);
  const user = mockDb.rows('users').get('cust');
  expect(user.rewardPoints).toBe(100);
  expect(user['rewardPointsByVenue.v1.points']).toBe(100);
  expect(mockDb.rows('rewardVouchers').get('r1')).toMatchObject({ status: 'expired', refunded: true });
  expect(mockDb.rows('rewardEvents').get('refund:r1')).toMatchObject({ type: 'redemption_refund', points: 100 });
});

test('a given ticket never refunds', async () => {
  issue('r1');
  await svc.markGiven('cust', 'r1', t0 + MIN);
  expect(await svc.expireOne('r1', t0 + 60 * MIN)).toBe(false);
  expect(mockDb.rows('users').get('cust').rewardPoints).toBe(0);
});

test('a ticket past its time reads as expired before the sweep runs', () => {
  const voucher = { status: 'issued', expiresAt: new Date(t0).toISOString() };
  expect(svc.effectiveStatus(voucher, t0 + MIN)).toBe('issued');
  expect(svc.effectiveStatus(voucher, t0 + 3 * MIN)).toBe('expired');
  expect(svc.publicVoucher({ ...voucher, voucherId: 'x' }, t0 + 3 * MIN)).toMatchObject({ status: 'expired', refunded: true });
});
