const shape = require('../ownActivity/shape');

const ts = (iso) => ({ toDate: () => new Date(iso) });

describe('own activity: categories and rows', () => {
  test('every timeline type has a category; noise types have none', () => {
    expect(shape.categoryOf('check_in')).toBe('checkins');
    expect(shape.categoryOf('video_uploaded')).toBe('moments');
    expect(shape.categoryOf('postcard_sent')).toBe('sent');
    expect(shape.categoryOf('place_liked')).toBe('social');
    expect(shape.categoryOf('profile_updated')).toBeNull();
    expect(shape.belongs({ type: 'check_in' }, 'checkins')).toBe(true);
    expect(shape.belongs({ type: 'check_in' }, 'moments')).toBe(false);
    expect(shape.belongs({ type: 'activity_notification' }, 'all')).toBe(false);
    expect(shape.normalizeFilter('bogus')).toBe('all');
  });

  test('a check-in row carries the place, note, rating, companions and privacy', () => {
    const item = shape.presentItem({
      id: 'a1', type: 'check_in', targetType: 'check_in', targetId: 'c1', targetName: "Tommy's Tavern", timestamp: ts('2026-09-25T22:40:00Z'),
      metadata: { placeId: 'p1', placePhoto: 'https://x/p.jpg', message: 'great wings', rating: 9, companions: ['Brittany'], ownerOnly: true }
    });
    expect(item).toMatchObject({ category: 'checkins', timestamp: '2026-09-25T22:40:00.000Z', placeId: 'p1', thumbnailUrl: 'https://x/p.jpg', message: 'great wings', rating: 9, companions: ['Brittany'], isPrivate: true });
  });

  test('a moment row takes its counts from extras and its thumbnail from the video', () => {
    const item = shape.presentItem({ id: 'a2', type: 'video_uploaded', targetType: 'video', targetId: 'v1', targetName: 'Stadium', timestamp: ts('2026-09-25T20:00:00Z'), metadata: { videoThumbnail: 'https://x/t.jpg', contentType: 'video' } }, { likeCount: 14, commentCount: 3 });
    expect(item).toMatchObject({ category: 'moments', thumbnailUrl: 'https://x/t.jpg', likeCount: 14, commentCount: 3, isPrivate: false });
  });
});

describe('own activity: the month summary', () => {
  const tz = 'America/New_York';
  const now = new Date('2026-09-25T16:00:00Z'); // Friday

  test('month bounds are local midnights, and default to the month of now', () => {
    const b = shape.monthBounds('2026-09', { timezone: tz });
    expect(b.start.toISOString()).toBe('2026-09-01T04:00:00.000Z');
    expect(b.end.toISOString()).toBe('2026-10-01T04:00:00.000Z');
    expect(shape.monthBounds(undefined, { now, timezone: tz }).key).toBe('2026-09');
    expect(shape.monthBounds('2026-12', { timezone: tz }).end.toISOString()).toBe('2027-01-01T05:00:00.000Z');
  });

  test('the streak counts consecutive weeks with a check-in, ending this week or last', () => {
    expect(shape.checkInStreakWeeks(['2026-09-24', '2026-09-16', '2026-09-08', '2026-09-01'], { now, timezone: tz })).toBe(4);
    expect(shape.checkInStreakWeeks(['2026-09-16', '2026-09-08'], { now, timezone: tz })).toBe(2); // nothing yet this week: last week still counts
    expect(shape.checkInStreakWeeks(['2026-09-08'], { now, timezone: tz })).toBe(0); // a gap breaks it
    expect(shape.checkInStreakWeeks([], { now, timezone: tz })).toBe(0);
    expect(shape.weekKey('2026-01-01')).toBe('2026-W01');
    expect(shape.weekKey('2026-12-31')).toBe('2026-W53');
  });

  test('counts, most visited, private count and on-this-day', () => {
    const rows = [
      { type: 'check_in', targetName: "Tommy's Tavern", timestamp: ts('2026-09-24T22:00:00Z'), metadata: {} },
      { type: 'check_in', targetName: "Tommy's Tavern", timestamp: ts('2026-09-17T22:00:00Z'), metadata: { ownerOnly: true } },
      { type: 'check_in', targetName: 'Atrium Health', timestamp: ts('2026-09-10T13:00:00Z'), metadata: { isPrivate: true } },
      { type: 'place_added', targetName: 'Pasta', timestamp: ts('2026-09-20T13:00:00Z'), metadata: {} },
      { type: 'video_uploaded', targetName: 'Stadium', timestamp: ts('2026-09-20T13:00:00Z'), metadata: {} },
      { type: 'postcard_sent', targetName: 'Mom', timestamp: ts('2026-09-21T13:00:00Z'), metadata: {} },
      { type: 'fridgemail_sent', targetName: 'Grandma', timestamp: ts('2026-09-22T13:00:00Z'), metadata: {} },
      { type: 'place_liked', targetName: 'x', timestamp: ts('2026-09-22T13:00:00Z'), metadata: {} },
      { type: 'profile_updated', timestamp: ts('2026-09-22T13:00:00Z'), metadata: {} }
    ];
    const s = shape.summarize(rows, { now, timezone: tz, pastYearCheckIns: [{ type: 'check_in', targetName: 'Pier 39', timestamp: ts('2025-09-25T18:00:00Z'), metadata: { placeId: 'p9' } }] });
    expect(s.counts).toEqual({ checkins: 3, places: 1, moments: 1, sent: 2, social: 1, postcards: 1 });
    expect(s.mostVisited).toEqual({ name: "Tommy's Tavern", count: 2 });
    expect(s.privateCheckIns).toBe(2);
    expect(s.streakWeeks).toBe(3);
    expect(s.onThisDay).toEqual([{ placeName: 'Pier 39', placeId: 'p9', at: '2025-09-25T18:00:00.000Z' }]);
  });
});
