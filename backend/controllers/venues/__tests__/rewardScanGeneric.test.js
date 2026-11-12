// The generic "Join FavCircles" code (JOINUS) is not a store: a scan of it
// never saves the demo venue or pays store points — it answers kind
// 'generic' so the app starts the person on their own first favorite
// (Wes, 2026-11-09: "the FavCircles virtual store is just a demo").
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const mockSave = jest.fn();
const mockStickerSave = jest.fn(async () => ({ awarded: true, points: 100 }));
jest.mock('../../../services/rewardService', () => ({
  findVenueByCode: async () => ({ venueId: 'cXpNZ3e11CTFTu1VuS4x', venueName: 'FavCircles', kind: 'window', genericJoin: true, isVirtual: true, offers: [] }),
  awardStickerSave: (...a) => mockStickerSave(...a),
  getBalance: async () => ({ rewardPoints: 50, venueBalances: [] }),
  effectiveEarnRate: () => 25,
  effectiveSavePoints: () => 100,
  incrementVenueStats: () => {}
}));
jest.mock('../../../services/ownerSubscriptionService', () => ({
  isVenueLoyaltyActive: async () => true,
  registerScanEarns: async () => ({ earns: true, demo: false, status: {} }),
  loyaltyNeverStarted: async () => false
}));
jest.mock('../../../services/clipStoreSave', () => ({ saveStoreForClip: (...a) => { mockSave(...a); return { saved: true }; } }));
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

test('JOINUS from the app or the clip: kind generic, nothing saved, no store points', async () => {
  for (const body of [{ code: 'JOINUS' }, { code: 'JOINUS', save: true }]) {
    const out = await run(body);
    expect(out.data).toMatchObject({ kind: 'generic', generic: true, awarded: null, saved: false, alreadySaved: false, loyaltyLive: false, balance: 50 });
    expect(out.data.venue).toMatchObject({ venueName: 'FavCircles', genericJoin: true });
  }
  expect(mockSave).not.toHaveBeenCalled();
  expect(mockStickerSave).not.toHaveBeenCalled();
});

test('code-name answers the kind too: generic for JOINUS (no store name)', async () => {
  const { codeName } = require('../rewardScanController');
  let out;
  const res = { status() { return this; }, json(b) { out = b; return this; } };
  await codeName({ params: { code: 'joinus' } }, res);
  expect(out).toEqual({ success: true, data: { venueName: null, kind: 'generic' } });
});
