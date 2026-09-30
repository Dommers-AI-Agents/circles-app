const { foldCheckInStats, unionIds, photosToCarry } = require('../venueMerge');

describe('foldCheckInStats', () => {
  // Sal at the Atlantic Club: 12 check-ins on one record, 5 recent on the other
  const survivor = { count: 12, firstCheckInAt: '2025-08-16T16:00:19Z', lastCheckInAt: '2026-09-20T18:24:25Z', placeName: 'Genesis Health Clubs', lastPlaceId: 'hzd', lastCheckInId: 'c12' };
  const retired = { count: 5, firstCheckInAt: '2026-09-23T17:48:04Z', lastCheckInAt: '2026-09-30T17:13:53Z', placeName: 'Genesis/Atlantic Health Club', lastPlaceId: '5q6', lastCheckInId: 'c5' };

  test('counts add; first is earliest, last is latest with its details', () => {
    expect(foldCheckInStats(survivor, retired)).toEqual({
      count: 17,
      firstCheckInAt: '2025-08-16T16:00:19Z',
      lastCheckInAt: '2026-09-30T17:13:53Z',
      placeName: 'Genesis/Atlantic Health Club',
      lastPlaceId: '5q6',
      lastCheckInId: 'c5'
    });
  });

  test('either side missing', () => {
    expect(foldCheckInStats(survivor, null)).toBe(survivor);
    expect(foldCheckInStats(null, retired)).toEqual(retired);
    expect(foldCheckInStats(null, null)).toBeNull();
  });
});

describe('unionIds', () => {
  test('keeps order, drops repeats and blanks', () => {
    expect(unionIds(['a', 'b'], ['b', 'c', null], [])).toEqual(['a', 'b', 'c']);
  });
});

describe('photosToCarry', () => {
  test('only photos the survivor lacks, either shape, no repeats', () => {
    const survivor = [{ url: 'u1' }];
    const retired = [{ id: 'p', url: 'u1' }, { id: 'q', url: 'u2', likes: ['w'] }, 'u3', 'u3', null];
    expect(photosToCarry(survivor, retired)).toEqual([{ id: 'q', url: 'u2', likes: ['w'] }, 'u3']);
  });
});
