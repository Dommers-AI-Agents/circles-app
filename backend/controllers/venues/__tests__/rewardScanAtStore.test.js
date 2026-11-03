// Where the phone was is stamped on every register visit for the owner; it
// never costs the customer the points (Wes, 2026-11-03: far, off and unknown
// all earn). Before that a far scan earned nothing (2026-10-31 / 11-02).
// Scans that earn nothing are logged for the owner's Activity (2026-11-03).
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const mockAward = jest.fn(async () => ({ awarded: true, points: 25 }));
const mockAttempt = jest.fn(async () => {});
jest.mock('../../../services/scanAttempts', () => ({ recordScanAttempt: (...a) => mockAttempt(...a) }));
jest.mock('../../../services/rewardService', () => ({
  findVenueByCode: async () => ({ venueId: 'v1', venueName: 'Test Bakery', kind: 'register', offers: [], location: { lat: 35.2161, lng: -80.858 } }),
  awardVenueVisit: (...a) => mockAward(...a),
  getBalance: async () => ({ rewardPoints: 0, venueBalances: [] }),
  effectiveEarnRate: () => 25,
  effectiveSavePoints: () => 0,
  incrementVenueStats: () => {}
}));
jest.mock('../../../services/ownerSubscriptionService', () => ({
  registerScanEarns: async () => ({ earns: true, demo: false, status: {} }),
  loyaltyNeverStarted: async () => false
}));
jest.mock('../../../services/ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => null }));
jest.mock('../../../services/nearbyEventsService', () => ({}));
jest.mock('../../../services/liveVenues', () => ({ listLiveVenues: async () => [] }));
const { scan } = require('../rewardScanController');

const run = async (body) => {
  let out;
  const res = { status() { return this; }, json(b) { out = b; return this; } };
  await scan({ user: { uid: 'u1' }, body }, res);
  return out;
};

describe('register scan atStore', () => {
  beforeEach(() => { mockAward.mockClear(); mockAttempt.mockClear(); });

  test('atStore false still earns, stamped far for the owner', async () => {
    const out = await run({ code: 'REG001', atStore: false });
    expect(mockAward.mock.calls[0][2]).toEqual({ location: 'far' });
    expect(out.data).toMatchObject({ kind: 'register', awarded: { type: 'venue_visit', points: 25 }, loyaltyLive: true });
    expect(out.data.notAtStore).toBeUndefined();
  });

  test('missing or true: points as before', async () => {
    for (const body of [{ code: 'REG001' }, { code: 'REG001', atStore: true }]) {
      const out = await run(body);
      expect(out.data.awarded).toEqual({ type: 'venue_visit', points: 25 });
    }
    expect(mockAward).toHaveBeenCalledTimes(2);
  });

  test("the app's fix far from the store still earns, stamped far; nothing extra logged", async () => {
    const out = await run({ code: 'REG001', location: { latitude: 35.27, longitude: -80.858, accuracy: 10 } });
    expect(mockAward.mock.calls[0][2]).toEqual({ location: 'far' });
    expect(mockAttempt).not.toHaveBeenCalled();
    expect(out.data.awarded).toEqual({ type: 'venue_visit', points: 25 });
  });

  test("the app's fix at the store earns, stamped near; location off earns, stamped off", async () => {
    await run({ code: 'REG001', location: { latitude: 35.2162, longitude: -80.858, accuracy: 30 } });
    await run({ code: 'REG001', locationOff: true });
    expect(mockAward.mock.calls.map((c) => c[2])).toEqual([{ location: 'near' }, { location: 'off' }]);
    expect(mockAttempt).not.toHaveBeenCalled();
  });

  test('a scan that earns nothing (already today, removed) is logged for the owner', async () => {
    mockAward.mockResolvedValueOnce({ awarded: false, duplicate: true, reason: 'already_today' });
    mockAward.mockResolvedValueOnce({ awarded: false, reason: 'removed' });
    await run({ code: 'REG001', location: { latitude: 35.2162, longitude: -80.858, accuracy: 30 } });
    await run({ code: 'REG001' });
    expect(mockAttempt.mock.calls.map((c) => c[2])).toEqual([
      { reason: 'already_today', location: 'near' },
      { reason: 'removed', location: 'unknown' }
    ]);
  });
});
