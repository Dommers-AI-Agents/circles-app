// The clip's preview for a points sticker or Favvy (window link + its tag,
// 2026-11-20) reads as a register code: the earn card, the visit's points.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: { increment: () => 0 } }));
jest.mock('../../services/rewardService', () => ({
  findVenueByCode: async () => ({
    venueId: 'v1', venueName: 'Vero', kind: 'window', windowCode: 'WIN123', offers: [],
    nfcStickers: { favvy: { label: 'Favvy', kind: 'register' }, 'table-7': { label: 'Table 7' } }
  }),
  incrementVenueStats: () => {},
  effectiveEarnRate: () => 25,
  effectiveSavePoints: () => 10,
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`
}));
jest.mock('../../services/ownerSubscriptionService', () => ({
  registerScanEarns: async () => ({ earns: true }),
  isVenueLoyaltyActive: async () => true,
  isVenueBusinessLive: async () => false
}));
jest.mock('../../services/placePhotoService', () => ({ venueCoverUrl: async () => null }));
jest.mock('../../services/waitlistService', () => ({ waitlistFor: async () => null }));
jest.mock('../../services/nfcStickerService', () => ({
  ...jest.requireActual('../../services/nfcStickerService'),
  recordTap: async () => true
}));
const { getVenuePreview } = require('../clipController');

const preview = async (t) => {
  let out;
  const res = { status() { return this; }, json(b) { out = b; return this; } };
  await getVenuePreview({ params: { code: 'WIN123' }, query: t ? { t } : {} }, res);
  return out.data;
};

test('a points sticker tag shows the earn card with the visit points', async () => {
  expect(await preview('favvy')).toMatchObject({ kind: 'register', scanPointsKind: 'visit', scanPoints: 25 });
});

test('a window sticker, or no tag, stays the save card', async () => {
  for (const t of ['table-7', undefined]) {
    expect(await preview(t)).toMatchObject({ kind: 'window', scanPointsKind: 'save', scanPoints: 10 });
  }
});
