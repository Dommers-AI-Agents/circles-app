// A register ("Points") NFC sticker or a Favvy figure (2026-11-20): the window
// link plus that sticker's tag (?t=) pays the visit like a register card. A
// window sticker's tag, an unknown tag, or no tag stays a window scan.
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const mockVisit = jest.fn(async () => ({ awarded: true, points: 25 }));
const mockSaveBonus = jest.fn(async () => ({ awarded: false }));
const mockClipSave = jest.fn(async () => ({ saved: true }));
let mockSavedBefore = null;
let mockEarns = true;
jest.mock('../../../services/storeCoupons', () => ({ claim: async () => null, issueTicket: async () => null }));
jest.mock('../../../services/storeWelcomeEmailService', () => ({ maybeSendAfterScan: async () => ({}) }));
jest.mock('../../../services/rewardService', () => ({
  findVenueByCode: async () => ({
    venueId: 'v1', venueName: 'Vero', kind: 'window', offers: [], windowCode: 'WIN123',
    nfcStickers: { favvy: { label: 'Favvy', kind: 'register' }, 'table-7': { label: 'Table 7', kind: 'window' } }
  }),
  awardStickerSave: (...a) => mockSaveBonus(...a),
  awardVenueVisit: (...a) => mockVisit(...a),
  getBalance: async () => ({ rewardPoints: 0, venueBalances: [] }),
  effectiveEarnRate: () => 25,
  effectiveSavePoints: () => 25,
  incrementVenueStats: () => {},
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`
}));
jest.mock('../../../services/ownerSubscriptionService', () => ({
  isVenueLoyaltyActive: async () => true,
  registerScanEarns: async () => ({ earns: mockEarns, demo: false, status: { reason: mockEarns ? 'paid' : 'lapsed' } }),
  loyaltyNeverStarted: async () => false
}));
jest.mock('../../../services/clipStoreSave', () => ({ saveStoreForClip: (...a) => mockClipSave(...a) }));
jest.mock('../../../services/ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => mockSavedBefore }));
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

beforeEach(() => {
  mockVisit.mockClear(); mockSaveBonus.mockClear(); mockClipSave.mockClear();
  mockSavedBefore = null; mockEarns = true;
});

test('the window code with a points sticker tag pays the visit like a register card', async () => {
  const out = await run({ code: 'WIN123', t: 'favvy' });
  expect(mockVisit).toHaveBeenCalledTimes(1);
  expect(out.data).toMatchObject({ kind: 'register', awarded: { type: 'venue_visit', points: 25 }, loyaltyLive: true });
  expect(mockSaveBonus).not.toHaveBeenCalled();
});

test('the tag matches however it is typed (Favvy → favvy)', async () => {
  const out = await run({ code: 'WIN123', t: 'Favvy' });
  expect(out.data.kind).toBe('register');
});

test('from the App Clip (save: true) a newcomer is saved too, then paid', async () => {
  const out = await run({ code: 'WIN123', t: 'favvy', save: true });
  expect(mockClipSave).toHaveBeenCalledTimes(1);
  expect(out.data).toMatchObject({ kind: 'register', saved: true, alreadySaved: true, awarded: { points: 25 } });
});

test('someone who already saved the store is not saved again', async () => {
  mockSavedBefore = { id: 'p1', data: () => ({}) };
  const out = await run({ code: 'WIN123', t: 'favvy', save: true });
  expect(mockClipSave).not.toHaveBeenCalled();
  expect(out.data).toMatchObject({ alreadySaved: true });
  expect(out.data.saved).toBeUndefined();
});

test('the same safeguards as a register card: far from the store earns nothing', async () => {
  const out = await run({ code: 'WIN123', t: 'favvy', atStore: false });
  expect(mockVisit).not.toHaveBeenCalled();
  expect(out.data).toMatchObject({ kind: 'register', awarded: null, notAtStore: true });
});

test('a store whose rewards are not live pays nothing, and the clip still saves', async () => {
  mockEarns = false;
  const out = await run({ code: 'WIN123', t: 'favvy', save: true });
  expect(mockVisit).not.toHaveBeenCalled();
  expect(out.data).toMatchObject({ kind: 'register', awarded: null, loyaltyPaused: true, saved: true });
});

test('a window sticker tag, an unknown tag, or no tag stays a window scan', async () => {
  for (const body of [{ code: 'WIN123', t: 'table-7' }, { code: 'WIN123', t: 'made-up' }, { code: 'WIN123' }]) {
    const out = await run(body);
    expect(out.data.kind).toBe('window');
  }
  expect(mockVisit).not.toHaveBeenCalled();
});
