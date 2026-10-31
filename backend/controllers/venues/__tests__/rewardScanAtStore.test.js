// A register scan the App Clip's location check says is away from the store
// earns no visit points (2026-10-31); missing atStore changes nothing.
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const mockAward = jest.fn(async () => ({ awarded: true, points: 25 }));
jest.mock('../../../services/rewardService', () => ({
  findVenueByCode: async () => ({ venueId: 'v1', venueName: 'Test Bakery', kind: 'register', offers: [] }),
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
  beforeEach(() => mockAward.mockClear());

  test('atStore false: no points, says why, still answers with the store', async () => {
    const out = await run({ code: 'REG001', atStore: false });
    expect(mockAward).not.toHaveBeenCalled();
    expect(out.data).toMatchObject({ kind: 'register', awarded: null, notAtStore: true, loyaltyLive: true });
  });

  test('missing or true: points as before', async () => {
    for (const body of [{ code: 'REG001' }, { code: 'REG001', atStore: true }]) {
      const out = await run(body);
      expect(out.data.awarded).toEqual({ type: 'venue_visit', points: 25 });
      expect(out.data.notAtStore).toBeUndefined();
    }
    expect(mockAward).toHaveBeenCalledTimes(2);
  });
});
