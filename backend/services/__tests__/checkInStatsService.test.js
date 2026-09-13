// The pure fold shared by the live transaction and the backfill. Firestore is
// never touched here.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) }),
  FieldValue: {}
}));
jest.mock('../globalPlaceResolver', () => ({
  ensureGlobalPlaceLink: jest.fn(),
  findCanonicalByNameAndLocation: jest.fn()
}));

const { applyCheckIn, toApi } = require('../checkInStatsService');

describe('applyCheckIn', () => {
  it('starts a bucket from the first check-in', () => {
    const s = applyCheckIn(null, { at: '2026-09-05T11:00:00.000Z', placeName: 'Crunch', placeId: 'p1', checkInId: 'c1' });
    expect(s).toEqual({
      count: 1,
      firstCheckInAt: '2026-09-05T11:00:00.000Z',
      lastCheckInAt: '2026-09-05T11:00:00.000Z',
      placeName: 'Crunch',
      lastPlaceId: 'p1',
      lastCheckInId: 'c1'
    });
  });

  it('increments and advances last for a newer check-in', () => {
    const first = applyCheckIn(null, { at: '2026-09-05T11:00:00.000Z', placeName: 'Crunch', placeId: 'p1', checkInId: 'c1' });
    const s = applyCheckIn(first, { at: '2026-09-08T11:00:00.000Z', placeName: 'Crunch Fitness', placeId: 'p2', checkInId: 'c2' });
    expect(s.count).toBe(2);
    expect(s.firstCheckInAt).toBe('2026-09-05T11:00:00.000Z');
    expect(s.lastCheckInAt).toBe('2026-09-08T11:00:00.000Z');
    expect(s.placeName).toBe('Crunch Fitness');
    expect(s.lastPlaceId).toBe('p2');
  });

  it('is order-independent: an older check-in folded later only moves first', () => {
    const newer = applyCheckIn(null, { at: '2026-09-08T11:00:00.000Z', placeName: 'New name', placeId: 'p2', checkInId: 'c2' });
    const s = applyCheckIn(newer, { at: '2026-09-05T11:00:00.000Z', placeName: 'Old name', placeId: 'p1', checkInId: 'c1' });
    expect(s.count).toBe(2);
    expect(s.firstCheckInAt).toBe('2026-09-05T11:00:00.000Z');
    expect(s.lastCheckInAt).toBe('2026-09-08T11:00:00.000Z');
    expect(s.placeName).toBe('New name');
    expect(s.lastPlaceId).toBe('p2');
    expect(s.lastCheckInId).toBe('c2');
  });

  it('keeps a known name when the newest check-in has none', () => {
    const first = applyCheckIn(null, { at: '2026-09-05T11:00:00.000Z', placeName: 'Crunch', placeId: 'p1', checkInId: 'c1' });
    const s = applyCheckIn(first, { at: '2026-09-08T11:00:00.000Z', placeName: null, placeId: null, checkInId: 'c2' });
    expect(s.placeName).toBe('Crunch');
    expect(s.lastPlaceId).toBe('p1');
  });
});

describe('toApi', () => {
  it('serves count and timestamps only', () => {
    expect(toApi({ count: 3, firstCheckInAt: 'a', lastCheckInAt: 'b', placeName: 'x', lastCheckInId: 'c' }))
      .toEqual({ count: 3, firstCheckInAt: 'a', lastCheckInAt: 'b' });
  });
  it('is null for an empty or missing bucket', () => {
    expect(toApi(null)).toBeNull();
    expect(toApi({ count: 0 })).toBeNull();
  });
});
