import { describe, expect, it } from 'vitest';
import { clockText, hoursStatus, minutesOf, weekRows, type HoursRowLike } from './openingHours';

// 2026-11-22 is a Sunday; at(1, 9, 30) is Monday 9:30 in the reader's own clock
const at = (day: number, hour: number, minute = 0) => new Date(2026, 10, 22 + day, hour, minute);

// The demo bakery: closed Sunday, 7–3 on weekdays (5 on Friday), 8–5 Saturday
const bakery: HoursRowLike[] = [
  { day: 0, open: null, close: null, isClosed: true },
  { day: 1, open: '07:00', close: '15:00', isClosed: false },
  { day: 2, open: '07:00', close: '15:00', isClosed: false },
  { day: 3, open: '07:00', close: '15:00', isClosed: false },
  { day: 4, open: '07:00', close: '15:00', isClosed: false },
  { day: 5, open: '07:00', close: '17:00', isClosed: false },
  { day: 6, open: '08:00', close: '17:00', isClosed: false }
];

// A bar: 6 PM to 2 AM Thursday to Saturday, closed the rest
const bar: HoursRowLike[] = [0, 1, 2, 3].map((day) => ({ day, isClosed: true } as HoursRowLike))
  .concat([4, 5, 6].map((day) => ({ day, open: '18:00', close: '02:00' })));

describe('times', () => {
  it('reads a time of day', () => {
    expect(minutesOf('09:00')).toBe(540);
    expect(minutesOf('24:00')).toBe(1440);
    expect(minutesOf('9am')).toBeNull();
    expect(minutesOf('25:00')).toBeNull();
    expect(minutesOf(null)).toBeNull();
  });
  it('writes one the way people say it', () => {
    expect(clockText(540)).toBe('9:00 AM');
    expect(clockText(0)).toBe('12:00 AM');
    expect(clockText(12 * 60 + 5)).toBe('12:05 PM');
    expect(clockText(17 * 60 + 30)).toBe('5:30 PM');
    expect(clockText(1440 + 120)).toBe('2:00 AM');
  });
});

describe('open now', () => {
  it('is open during the day and says when it closes', () => {
    expect(hoursStatus(bakery, at(1, 9, 30))).toEqual({ open: true, text: 'Open now · closes 3:00 PM' });
  });
  it('is open at the opening minute and closed at the closing minute', () => {
    expect(hoursStatus(bakery, at(1, 7, 0))?.open).toBe(true);
    expect(hoursStatus(bakery, at(1, 15, 0))?.open).toBe(false);
  });
  it('says when it opens later today', () => {
    expect(hoursStatus(bakery, at(1, 6, 15))).toEqual({ open: false, text: 'Closed · opens 7:00 AM' });
  });
  it('says tomorrow once today is over', () => {
    expect(hoursStatus(bakery, at(1, 20))).toEqual({ open: false, text: 'Closed · opens tomorrow at 7:00 AM' });
    expect(hoursStatus(bakery, at(0, 12))).toEqual({ open: false, text: 'Closed · opens tomorrow at 7:00 AM' });
  });
  it('names the day when it is further off, across the end of the week', () => {
    expect(hoursStatus(bakery, at(6, 18))).toEqual({ open: false, text: 'Closed · opens Monday at 7:00 AM' });
    expect(hoursStatus(bar, at(1, 12))).toEqual({ open: false, text: 'Closed · opens Thursday at 6:00 PM' });
  });
});

describe('hours that run past midnight', () => {
  it('is open late in the evening, closing in the small hours', () => {
    expect(hoursStatus(bar, at(5, 23))).toEqual({ open: true, text: 'Open now · closes 2:00 AM' });
  });
  it('is still open after midnight on the next day, though that day has its own row', () => {
    expect(hoursStatus(bar, at(6, 1, 30))).toEqual({ open: true, text: 'Open now · closes 2:00 AM' });
  });
  it('is still open early Sunday from Saturday night, on a day marked closed', () => {
    expect(hoursStatus(bar, at(0, 1))).toEqual({ open: true, text: 'Open now · closes 2:00 AM' });
    expect(hoursStatus(bar, at(0, 2))).toEqual({ open: false, text: 'Closed · opens Thursday at 6:00 PM' });
  });
  it('closes at midnight when the close is 00:00', () => {
    const cafe: HoursRowLike[] = [{ day: 2, open: '16:00', close: '00:00' }, { day: 3, isClosed: true }];
    expect(hoursStatus(cafe, at(2, 23, 59))).toEqual({ open: true, text: 'Open now · closes 12:00 AM' });
    expect(hoursStatus(cafe, at(3, 0, 0))?.open).toBe(false);
  });
});

describe('open all day', () => {
  const always: HoursRowLike[] = [0, 1, 2, 3, 4, 5, 6].map((day) => ({ day, open: '00:00', close: '23:59' }));
  it('never closes when every day is 24 hours', () => {
    expect(hoursStatus(always, at(3, 4))).toEqual({ open: true, text: 'Open now · open 24 hours' });
    expect(hoursStatus(always, at(6, 23, 59))).toEqual({ open: true, text: 'Open now · open 24 hours' });
  });
  it('treats 00:00–24:00 the same', () => {
    expect(hoursStatus([{ day: 1, open: '00:00', close: '24:00' }, { day: 2, isClosed: true }], at(1, 12)))
      .toEqual({ open: true, text: 'Open now · closes 12:00 AM' });
  });
  it('treats 00:00–00:00 as closed, like the iPhone app', () => {
    expect(hoursStatus([{ day: 1, open: '00:00', close: '00:00' }], at(1, 12))).toEqual({ open: false, text: 'Closed' });
  });
});

describe('missing hours', () => {
  it('says nothing when there are none', () => {
    expect(hoursStatus(null, at(1, 12))).toBeNull();
    expect(hoursStatus(undefined, at(1, 12))).toBeNull();
    expect(hoursStatus([], at(1, 12))).toBeNull();
  });
  it('says nothing when today has no row, or a row with no times', () => {
    expect(hoursStatus([{ day: 1, open: '07:00', close: '15:00' }], at(2, 12))).toBeNull();
    expect(hoursStatus([{ day: 2, open: null, close: null, isClosed: false }], at(2, 12))).toBeNull();
    expect(hoursStatus([{ day: 2, open: 'morning', close: 'late' }], at(2, 12))).toBeNull();
  });
  it('still knows it is open from yesterday when today is unknown', () => {
    expect(hoursStatus([{ day: 5, open: '20:00', close: '03:00' }], at(6, 1))?.open).toBe(true);
  });
  it('is just "Closed" when every listed day is closed', () => {
    expect(hoursStatus([{ day: 2, isClosed: true }], at(2, 12))).toEqual({ open: false, text: 'Closed' });
  });
});

describe('the week', () => {
  it('starts today and writes each day', () => {
    const week = weekRows(bakery, at(5, 10));
    expect(week.map((row) => row.name)).toEqual(['Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu']);
    expect(week[0]).toEqual({ day: 5, name: 'Fri', text: '7:00 AM – 5:00 PM', today: true });
    expect(week[2].text).toBe('Closed');
  });
  it('joins split hours and marks days nobody listed', () => {
    const split: HoursRowLike[] = [{ day: 1, open: '17:00', close: '22:00' }, { day: 1, open: '11:00', close: '14:00' }, { day: 2, open: '00:00', close: '23:59' }];
    const week = weekRows(split, at(1, 10));
    expect(week[0].text).toBe('11:00 AM – 2:00 PM, 5:00 PM – 10:00 PM');
    expect(week[1].text).toBe('Open 24 hours');
    expect(week[2].text).toBe('Not listed');
  });
  it('is empty when nothing is known', () => {
    expect(weekRows(null, at(1, 10))).toEqual([]);
    expect(weekRows([{ day: 1, open: null, close: null }], at(1, 10))).toEqual([]);
  });
});
