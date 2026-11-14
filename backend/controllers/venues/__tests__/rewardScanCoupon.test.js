// A flyer's QR is the window link plus ?c=<coupon> (2026-11-14): the window
// scan claims the coupon for the account and says so; the register scan
// turns a claimed coupon into the counter ticket beside the visit's points.
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const mockClaim = jest.fn(async () => ({ status: 'claimed', coupon: { couponId: 'ABCDEF', title: '20% off' }, claim: { claimId: 'v1_u1_ABCDEF', status: 'claimed' } }));
const mockTicket = jest.fn(async () => ({ claim: { claimId: 'v1_u1_ABCDEF', status: 'ticket' }, voucher: { voucherCode: 'C001', pointsCost: 0 }, already: false }));
jest.mock('../../../services/storeCoupons', () => ({
  claim: (...a) => mockClaim(...a),
  issueTicket: (...a) => mockTicket(...a),
  openAtVenue: async () => [],
  claimView: (c) => c
}));
const mockWelcome = jest.fn(async () => ({ sent: false }));
jest.mock('../../../services/storeWelcomeEmailService', () => ({ maybeSendAfterScan: (...a) => mockWelcome(...a) }));
let mockKind = 'window';
jest.mock('../../../services/rewardService', () => ({
  findVenueByCode: async () => ({ venueId: 'v1', venueName: 'Vero', kind: mockKind, offers: [], windowCode: 'WIN123' }),
  awardStickerSave: async () => ({ awarded: false }),
  awardVenueVisit: async () => ({ awarded: true, points: 25 }),
  getBalance: async () => ({ rewardPoints: 0, venueBalances: [] }),
  effectiveEarnRate: () => 25,
  effectiveSavePoints: () => 0,
  incrementVenueStats: () => {}
}));
jest.mock('../../../services/ownerSubscriptionService', () => ({
  isVenueLoyaltyActive: async () => true,
  registerScanEarns: async () => ({ earns: true, demo: false, status: {} }),
  loyaltyNeverStarted: async () => false
}));
jest.mock('../../../services/clipStoreSave', () => ({ saveStoreForClip: async () => ({ saved: true }) }));
jest.mock('../../../services/ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => null }));
jest.mock('../../../services/scanAttempts', () => ({ recordScanAttempt: async () => {} }));
jest.mock('../../../services/nearbyEventsService', () => ({}));
jest.mock('../../../services/liveVenues', () => ({ listLiveVenues: async () => [] }));
const { scan } = require('../rewardScanController');

const run = async (body) => {
  let out;
  const res = { status() { return this; }, json(b) { out = b; return this; } };
  await scan({ user: { uid: 'u1' }, body }, res);
  return out;
};

beforeEach(() => { mockClaim.mockClear(); mockTicket.mockClear(); mockWelcome.mockClear(); mockKind = 'window'; });

test('a window scan with c= claims the coupon and answers with it; the welcome email learns of it', async () => {
  const out = await run({ code: 'WIN123', c: 'abcdef', save: true });
  expect(mockClaim).toHaveBeenCalledTimes(1);
  expect(mockClaim.mock.calls[0][0]).toMatchObject({ couponId: 'abcdef', userId: 'u1', via: 'clip_scan' });
  expect(out.data.coupon).toMatchObject({ status: 'claimed', coupon: { title: '20% off' } });
  expect(mockWelcome.mock.calls[0][2].coupon).toEqual({ couponId: 'ABCDEF', title: '20% off' });
});

test('a window scan without a coupon claims nothing and says nothing about one', async () => {
  const out = await run({ code: 'WIN123' });
  expect(mockClaim).not.toHaveBeenCalled();
  expect(out.data.coupon).toBeUndefined();
});

test('the register scan opens the claimed coupon\'s ticket beside the points', async () => {
  mockKind = 'register';
  const out = await run({ code: 'REG001' });
  expect(mockTicket).toHaveBeenCalledWith({ userId: 'u1', venueId: 'v1' });
  expect(out.data.awarded).toEqual({ type: 'venue_visit', points: 25 });
  expect(out.data.coupon).toMatchObject({ status: 'ticket', voucher: { voucherCode: 'C001' } });
});

test('away from the store, no ticket either', async () => {
  mockKind = 'register';
  const out = await run({ code: 'REG001', atStore: false });
  expect(mockTicket).not.toHaveBeenCalled();
  expect(out.data.coupon).toBeUndefined();
});
