// Coupons (2026-11-14): the owner's coupon and its link, who may claim, the
// one-claim rule, the counter ticket (given = used, run out = back to
// claimed), the customer's list, and the campaign's numbers.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: MockFieldValue,
  admin: { firestore: { FieldValue: MockFieldValue } }
}));
const mockWallet = jest.fn();
let mockCodeN = 0;
jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  generateVoucherCode: () => `C${String(++mockCodeN).padStart(3, '0')}`,
  walletBalanceChanged: (...a) => mockWallet(...a),
  incrementVenueStats: jest.fn()
}));

const coupons = require('../storeCoupons');
const vouchers = require('../rewardVoucherService');

const NOW = new Date('2026-11-14T18:00:00.000Z');
const days = (n) => new Date(NOW.getTime() + n * 86400000).toISOString();
const MIN = 60 * 1000;

const mailer = { couponId: 'ABCDEF', title: '20% off any pickup order', detail: 'Max $20. Not valid for dine-in.', onlineCode: 'TGOSTVQC', campaign: 'Nov mailer', expiresAt: days(20), maxClaims: null, active: true, createdAt: days(-2), updatedAt: days(-2) };
const venue = () => ({ venueId: 'v1', venueName: 'Vero Chicago Pizza', windowCode: 'WIN123', coupons: [mailer], couponCounts: {} });
const refreshVenue = async () => ({ venueId: 'v1', ...(await mockDb.collection('stickerVenues').doc('v1').get()).data() });

beforeEach(async () => {
  mockCodeN = 0; mockWallet.mockClear();
  for (const name of ['stickerVenues', 'couponClaims', 'users', 'rewardEvents', 'rewardVouchers']) mockDb.rows(name).clear();
  await mockDb.collection('stickerVenues').doc('v1').set(venue());
  await mockDb.collection('users').doc('ana').set({ rewardPointsByVenue: { v1: { points: 100, purchases: 4 } } });
  await mockDb.collection('users').doc('ben').set({ displayName: 'Ben' });
});

describe('the coupon itself', () => {
  it('checks the owner\'s fields and keeps what an edit leaves out', () => {
    const made = coupons.normalizeCoupon({ title: ' 20% off any pickup order ', detail: 'Max $20', onlineCode: 'tgostvqc', campaign: 'Nov mailer', expiresAt: days(30), maxClaims: '500' }, { now: NOW });
    expect(made).toEqual({ title: '20% off any pickup order', detail: 'Max $20', campaign: 'Nov mailer', onlineCode: 'TGOSTVQC', expiresAt: days(30), maxClaims: 500, active: true });
    expect(coupons.normalizeCoupon({ title: 'Free slice', expiresAt: days(1) }, { now: NOW })).toMatchObject({ detail: null, onlineCode: null, campaign: null, maxClaims: null });
    expect(() => coupons.normalizeCoupon({ expiresAt: days(1) }, { now: NOW })).toThrow(/Say what the coupon gives/);
    expect(() => coupons.normalizeCoupon({ title: 'x', expiresAt: days(-1) }, { now: NOW })).toThrow(/already passed/);
    expect(() => coupons.normalizeCoupon({ title: 'x', expiresAt: days(400) }, { now: NOW })).toThrow(/at most a year/);
    expect(() => coupons.normalizeCoupon({ title: 'x', expiresAt: days(1), onlineCode: 'no spaces!' }, { now: NOW })).toThrow(/letters and numbers/);
    expect(() => coupons.normalizeCoupon({ title: 'x', expiresAt: days(1), maxClaims: 0 }, { now: NOW })).toThrow(/whole number/);
    expect(() => coupons.normalizeCoupon({ title: 'x', expiresAt: days(1), active: 'yes' }, { now: NOW })).toThrow(/on or off/);
    // An edit to a finished coupon (pausing it) doesn't trip over its old date
    const ended = { ...mailer, expiresAt: days(-3) };
    expect(coupons.normalizeCoupon({ active: false }, { now: NOW, existing: ended })).toMatchObject({ active: false, title: mailer.title, expiresAt: days(-3) });
    expect(() => coupons.normalizeCoupon({ expiresAt: days(-1) }, { now: NOW, existing: ended })).toThrow(/already passed/);
  });

  it('has a readable id, the store\'s window link with ?c=, and a state for the owner', () => {
    expect(coupons.newCouponId()).toMatch(coupons.ID_RE);
    expect(coupons.normalizeId(' abcdef ')).toBe('ABCDEF');
    expect(coupons.normalizeId('ABCD')).toBeNull();
    expect(coupons.couponUrl(venue(), 'ABCDEF')).toBe('https://api.favcircles.com/s/WIN123?c=ABCDEF');
    expect(coupons.ownerCoupon(venue(), mailer, NOW)).toMatchObject({ url: 'https://api.favcircles.com/s/WIN123?c=ABCDEF', state: 'live', counts: { scans: 0, claims: 0, redemptions: 0 } });
    expect(coupons.ownerCoupon(venue(), { ...mailer, active: false }, NOW).state).toBe('paused');
    expect(coupons.ownerCoupon(venue(), { ...mailer, expiresAt: days(-1) }, NOW).state).toBe('ended');
    expect(coupons.ownerCoupon({ ...venue(), couponCounts: { ABCDEF: { claims: 2 } } }, { ...mailer, maxClaims: 2 }, NOW).state).toBe('full');
  });

  it('creates, edits and removes on the store record, newest first', async () => {
    const v = venue();
    const { coupon } = await coupons.create(v, { title: 'Free garlic knots', expiresAt: days(10), campaign: 'Door hangers' }, { now: NOW });
    expect(coupon.couponId).toMatch(coupons.ID_RE);
    let fresh = await refreshVenue();
    expect(fresh.coupons.map((c) => c.title)).toEqual(['20% off any pickup order', 'Free garlic knots']);
    expect(coupons.listForOwner(fresh, NOW).map((c) => c.title)).toEqual(['Free garlic knots', '20% off any pickup order']);

    const edited = await coupons.update(fresh, coupon.couponId, { active: false, onlineCode: 'knots' }, { now: NOW });
    expect(edited.coupon).toMatchObject({ active: false, onlineCode: 'KNOTS', title: 'Free garlic knots', state: 'paused' });
    await expect(coupons.update(fresh, 'ZZZZZZ', { title: 'x' })).rejects.toMatchObject({ status: 404 });

    fresh = await refreshVenue();
    await coupons.remove(fresh, coupon.couponId, { now: NOW });
    fresh = await refreshVenue();
    expect(fresh.coupons.map((c) => c.couponId)).toEqual(['ABCDEF']);
    await expect(coupons.create({ ...fresh, coupons: new Array(20).fill(mailer) }, { title: 'x', expiresAt: days(1) })).rejects.toMatchObject({ code: 'too_many_coupons' });
  });
});

describe('claiming from the flyer', () => {
  it('says who may claim', () => {
    const live = { ...mailer };
    expect(coupons.claimVerdict({ coupon: live, now: NOW })).toBe('ok');
    expect(coupons.claimVerdict({ coupon: null, now: NOW })).toBe('not_found');
    expect(coupons.claimVerdict({ coupon: live, existing: { status: 'claimed' }, now: NOW })).toBe('already');
    expect(coupons.claimVerdict({ coupon: { ...live, active: false }, now: NOW })).toBe('paused');
    expect(coupons.claimVerdict({ coupon: { ...live, expiresAt: days(-1) }, now: NOW })).toBe('expired');
    expect(coupons.claimVerdict({ coupon: { ...live, maxClaims: 10 }, counts: { claims: 10 }, now: NOW })).toBe('full');
  });

  it('claims once per account, counts every scan, and knows a new customer from a regular', async () => {
    const first = await coupons.claim({ venue: venue(), couponId: 'abcdef', userId: 'ben', now: NOW });
    expect(first.status).toBe('claimed');
    expect(first.coupon).toEqual({ couponId: 'ABCDEF', title: mailer.title, detail: mailer.detail, onlineCode: 'TGOSTVQC', expiresAt: mailer.expiresAt });
    expect(first.claim).toMatchObject({ claimId: 'v1_ben_ABCDEF', status: 'claimed', venueName: 'Vero Chicago Pizza', onlineCode: 'TGOSTVQC' });
    expect(mockWallet).toHaveBeenCalledWith('ben', 'v1');

    const again = await coupons.claim({ venue: await refreshVenue(), couponId: 'ABCDEF', userId: 'ben', now: NOW });
    expect(again.status).toBe('already');
    expect(again.claim.status).toBe('claimed');

    const regular = await coupons.claim({ venue: await refreshVenue(), couponId: 'ABCDEF', userId: 'ana', now: NOW });
    expect(regular.status).toBe('claimed');
    const claims = mockDb.rows('couponClaims');
    expect(claims.get('v1_ben_ABCDEF').newCustomer).toBe(true);
    expect(claims.get('v1_ana_ABCDEF').newCustomer).toBe(false);

    const fresh = await refreshVenue();
    expect(fresh.couponCounts.ABCDEF).toEqual({ scans: 3, claims: 2 });
    expect(await coupons.claim({ venue: fresh, couponId: 'NOPE', userId: 'ben', now: NOW })).toEqual({ status: 'not_found', coupon: null, claim: null });
  });

  it('a full or finished coupon is still shown, not claimed', async () => {
    const full = { ...venue(), coupons: [{ ...mailer, maxClaims: 1 }], couponCounts: { ABCDEF: { claims: 1 } } };
    expect((await coupons.claim({ venue: full, couponId: 'ABCDEF', userId: 'ben', now: NOW })).status).toBe('full');
    expect(mockDb.rows('couponClaims').size).toBe(0);
    const ended = { ...venue(), coupons: [{ ...mailer, expiresAt: days(-1) }] };
    expect((await coupons.claim({ venue: ended, couponId: 'ABCDEF', userId: 'ben', now: NOW })).status).toBe('expired');
    expect(coupons.preview(venue(), 'ABCDEF', NOW)).toMatchObject({ title: mailer.title, available: true });
    expect(coupons.preview(ended, 'ABCDEF', NOW)).toMatchObject({ available: false });
    expect(coupons.preview(venue(), 'ZZZZZZ', NOW)).toBeNull();
  });
});

describe('the ticket at the counter', () => {
  const claimBen = () => coupons.claim({ venue: venue(), couponId: 'ABCDEF', userId: 'ben', now: NOW });

  it('the register scan opens a ticket for the coupon ending soonest; a second scan returns the same ticket', async () => {
    await claimBen();
    expect(await coupons.issueTicket({ userId: 'ana', venueId: 'v1', now: NOW })).toBeNull(); // nothing claimed
    const ticket = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW });
    expect(ticket.already).toBe(false);
    expect(ticket.claim).toMatchObject({ status: 'ticket', voucherId: expect.any(String) });
    expect(ticket.voucher).toMatchObject({ status: 'issued', pointsCost: 0, offerTitle: mailer.title, voucherCode: 'C001', couponId: 'ABCDEF', onlineCode: 'TGOSTVQC', refunded: false });
    expect(Date.parse(ticket.voucher.expiresAt) - NOW.getTime()).toBe(15 * MIN);
    const event = mockDb.rows('rewardEvents').get(ticket.voucher.voucherId);
    expect(event).toMatchObject({ type: 'coupon_redemption', points: 0, status: 'issued', couponId: 'ABCDEF', campaign: 'Nov mailer' });

    const again = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: new Date(NOW.getTime() + 2 * MIN) });
    expect(again.already).toBe(true);
    expect(again.voucher.voucherId).toBe(ticket.voucher.voucherId);
    expect(mockDb.rows('rewardVouchers').size).toBe(1);
  });

  it('staff tap Given: the coupon is used and the campaign counts it (and the new customer)', async () => {
    await claimBen();
    const { voucher } = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW });
    const given = await vouchers.markGiven('ben', voucher.voucherId, NOW.getTime() + 3 * MIN);
    expect(given).toMatchObject({ status: 'given', refunded: false, couponId: 'ABCDEF' });
    expect(mockDb.rows('couponClaims').get('v1_ben_ABCDEF')).toMatchObject({ status: 'used', usedAt: new Date(NOW.getTime() + 3 * MIN).toISOString() });
    expect((await refreshVenue()).couponCounts.ABCDEF).toEqual({ scans: 1, claims: 1, tickets: 1, redemptions: 1, newCustomers: 1 });
    // Used is used: no second ticket
    expect(await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW })).toBeNull();
    await expect(coupons.issueTicket({ userId: 'ben', venueId: 'v1', claimId: 'v1_ben_ABCDEF', now: NOW })).rejects.toMatchObject({ code: 'coupon_not_open' });
  });

  it('a ticket that runs out unshown goes back to claimed, with nothing to refund', async () => {
    await claimBen();
    const { voucher } = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW });
    const swept = await vouchers.expireDue(NOW.getTime() + 20 * MIN);
    expect(swept).toEqual({ checked: 1, expired: 1 });
    expect(mockDb.rows('couponClaims').get('v1_ben_ABCDEF')).toMatchObject({ status: 'claimed', voucherId: null });
    expect(mockDb.rows('rewardVouchers').get(voucher.voucherId)).toMatchObject({ status: 'expired', refunded: false });
    expect(mockDb.rows('rewardEvents').size).toBe(1); // no refund row for 0 points
    expect(mockDb.rows('users').get('ben').rewardPoints).toBeUndefined();
    // …and it can be opened again
    const later = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: new Date(NOW.getTime() + 30 * MIN) });
    expect(later.already).toBe(false);
    expect(later.voucher.voucherCode).toBe('C002');
  });

  it('a chosen coupon ("Use now") opens that one', async () => {
    const v = { ...venue(), coupons: [mailer, { ...mailer, couponId: 'KNTS22', title: 'Free garlic knots', onlineCode: null, expiresAt: days(5) }] };
    await coupons.claim({ venue: v, couponId: 'ABCDEF', userId: 'ben', now: NOW });
    await coupons.claim({ venue: v, couponId: 'KNTS22', userId: 'ben', now: NOW });
    const chosen = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', claimId: 'v1_ben_ABCDEF', now: NOW });
    expect(chosen.voucher.offerTitle).toBe('20% off any pickup order');
    // The register picks the one ending soonest among those still open
    const next = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW });
    expect(next.voucher.offerTitle).toBe('Free garlic knots');
  });
});

describe('the customer\'s list and the campaign table', () => {
  it('lists open coupons first, then used, then expired', async () => {
    const v = { ...venue(), coupons: [mailer, { ...mailer, couponId: 'BRDBNE', title: 'Old', expiresAt: days(1) }, { ...mailer, couponId: 'USEDUP', title: 'Used' }] };
    await coupons.claim({ venue: v, couponId: 'BRDBNE', userId: 'ben', now: new Date(NOW.getTime() - 3 * 86400000) });
    await coupons.claim({ venue: v, couponId: 'USEDUP', userId: 'ben', now: new Date(NOW.getTime() - 2 * 86400000) });
    await coupons.claim({ venue: v, couponId: 'ABCDEF', userId: 'ben', now: new Date(NOW.getTime() - 86400000) });
    const { voucher } = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', claimId: 'v1_ben_USEDUP', now: NOW });
    await vouchers.markGiven('ben', voucher.voucherId, NOW.getTime());
    const later = new Date(NOW.getTime() + 2 * 86400000); // "Old" has ended
    const list = await coupons.listForUser('ben', { now: later });
    expect(list.map((c) => [c.title, c.status])).toEqual([['20% off any pickup order', 'claimed'], ['Used', 'used'], ['Old', 'expired']]);
    expect((await coupons.openAtVenue('ben', 'v1', later)).map((c) => c.couponId)).toEqual(['ABCDEF']);
  });

  it('counts scans, claims, used, new customers and who came in after claiming', async () => {
    const v = venue();
    await coupons.claim({ venue: v, couponId: 'ABCDEF', userId: 'ben', now: NOW });
    await coupons.claim({ venue: v, couponId: 'ABCDEF', userId: 'ana', now: NOW });
    const { voucher } = await coupons.issueTicket({ userId: 'ben', venueId: 'v1', now: NOW });
    await vouchers.markGiven('ben', voucher.voucherId, NOW.getTime());
    const fresh = await refreshVenue();
    const claims = await coupons.claimsForVenue('v1');
    const visits = [{ type: 'venue_visit', userId: 'ben', createdAt: days(1) }, { type: 'venue_visit', userId: 'ana', createdAt: days(-5) }];
    expect(coupons.campaignRows({ venue: fresh, claims, visits, now: NOW })).toEqual([{
      couponId: 'ABCDEF', title: mailer.title, campaign: 'Nov mailer', expiresAt: mailer.expiresAt, state: 'live',
      scans: 2, claims: 2, used: 1, newCustomers: 1, cameIn: 1
    }]);
  });
});
