// The user's wall clock. Cloud Run is UTC; these pin the zone maths and the
// fallback that keeps a bad zone from silencing someone forever.
const { localClock, localDateKey, FALLBACK_ZONE } = require('../localClock');

// 2026-09-19T03:30:00Z is a Saturday: Friday evening in New York, Saturday
// midday in Tokyo. Both sides of a date line in one instant.
const instant = new Date('2026-09-19T03:30:00Z');

test('reads hour, minute, weekday and minutes-since-midnight in the given zone', () => {
  expect(localClock('America/New_York', instant)).toEqual({ hour: 23, minute: 30, weekday: 5, minutes: 23 * 60 + 30 });
  expect(localClock('Asia/Tokyo', instant)).toEqual({ hour: 12, minute: 30, weekday: 6, minutes: 12 * 60 + 30 });
  expect(localClock('UTC', instant)).toEqual({ hour: 3, minute: 30, weekday: 6, minutes: 210 });
});

test('midnight is hour 0, never 24', () => {
  expect(localClock('UTC', new Date('2026-09-19T00:05:00Z')).hour).toBe(0);
  expect(localClock('Europe/London', new Date('2026-09-18T23:05:00Z')).hour).toBe(0);
});

test('missing or unknown zones fall back to the historical Eastern treatment', () => {
  expect(FALLBACK_ZONE).toBe('America/New_York');
  const eastern = localClock('America/New_York', instant);
  expect(localClock(null, instant)).toEqual(eastern);
  expect(localClock('', instant)).toEqual(eastern);
  expect(localClock('Mars/Olympus_Mons', instant)).toEqual(eastern);
});

test('localDateKey is the calendar day in the zone, zero-padded', () => {
  expect(localDateKey('America/New_York', instant)).toBe('2026-09-18');
  expect(localDateKey('Asia/Tokyo', instant)).toBe('2026-09-19');
  expect(localDateKey('UTC', new Date('2026-01-05T12:00:00Z'))).toBe('2026-01-05');
  expect(localDateKey('Not/AZone', instant)).toBe('2026-09-18');
});
