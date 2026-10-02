// The Check In screen's header numbers.
const { summarize, friendsOut, weekOf } = require('../checkInSummary');

const NOW = Date.parse('2026-10-02T15:00:00Z'); // a Friday
const at = (iso, placeName, placeId) => ({ startTime: iso, placeName, placeId });

test('weeks start on Monday', () => {
  expect(weekOf(Date.parse('2026-09-28T00:00:00Z'))).toBe(weekOf(Date.parse('2026-10-04T23:59:00Z')));
  expect(weekOf(Date.parse('2026-09-27T23:59:00Z'))).not.toBe(weekOf(Date.parse('2026-09-28T00:00:00Z')));
});

test('totals, this month, distinct places, last place', () => {
  const s = summarize([
    at('2026-10-01T18:00:00Z', 'Sixty Vines', 'p1'),
    at('2026-09-20T18:00:00Z', 'Sixty Vines', 'p1'),
    at('2026-09-12T18:00:00Z', 'Muraya', 'p2')
  ], NOW);
  expect(s).toMatchObject({ total: 3, thisMonth: 1, places: 2, lastPlaceName: 'Sixty Vines', checkedInThisWeek: true });
});

test('streak counts back through consecutive weeks', () => {
  const s = summarize([
    at('2026-10-01T18:00:00Z', 'A'), at('2026-09-24T18:00:00Z', 'B'), at('2026-09-15T18:00:00Z', 'C'),
    at('2026-08-01T18:00:00Z', 'D')
  ], NOW);
  expect(s.weekStreak).toBe(3);
});

test('a streak is still alive before this week\'s first check-in', () => {
  const s = summarize([at('2026-09-24T18:00:00Z', 'B'), at('2026-09-16T18:00:00Z', 'C')], NOW);
  expect(s).toMatchObject({ weekStreak: 2, checkedInThisWeek: false });
  expect(summarize([at('2026-09-10T18:00:00Z', 'C')], NOW).weekStreak).toBe(0);
});

test('nothing yet', () => {
  expect(summarize([], NOW)).toMatchObject({ total: 0, places: 0, weekStreak: 0, lastPlaceName: null });
});

test('friends out: one row per person, never you', () => {
  const rows = friendsOut([
    { userId: 'me', userName: 'Wes', placeName: 'X' },
    { userId: 'b', userName: 'Brittany', placeName: 'Muraya' },
    { userId: 'b', userName: 'Brittany', placeName: 'Older' },
    { userId: 's', userName: 'Sal', userPhoto: 'p.jpg', placeName: 'Club' }
  ], 'me');
  expect(rows.map((r) => r.displayName)).toEqual(['Brittany', 'Sal']);
  expect(rows[0].placeName).toBe('Muraya');
});
