// The same cases as ios/Circles-iOS-UIKitTests/ChatTimelineTests.swift.
import { describe, expect, it } from 'vitest';
import { dateOf, dayTitle, receipt, rows, timeLabel, type Entry, type Row } from './chatTimeline';

const timeZone = 'America/New_York';
const locale = 'en-US';
// November 2026 in New York is UTC-5 (standard time since Nov 1)
const date = (day: number, hour: number, minute = 0, month = 11, year = 2026): Date =>
  new Date(Date.UTC(year, month - 1, day, hour + 5, minute));
const entry = (id: string, senderId: string, when: Date | null, mine = false, read = false): Entry =>
  ({ id, senderId, date: when, isMine: mine, readByOther: read });
const bubble = (id: string, startsRun: boolean, endsRun: boolean): Row => ({ kind: 'message', id, startsRun, endsRun });
const day = (title: string): Row => ({ kind: 'day', title });
const clock = { timeZone, locale, now: date(23, 12) }; // Monday

describe('rows', () => {
  it('the classic chat is one row per message', () => {
    const entries = [entry('a', 'me', date(22, 9), true), entry('b', 'me', date(23, 9, 1), true)];
    expect(rows(entries, { ...clock, grouped: false })).toEqual([bubble('a', true, true), bubble('b', true, true)]);
  });

  it('a new day gets a divider', () => {
    const entries = [entry('a', 'me', date(22, 21), true), entry('b', 'sunil', date(23, 10))];
    expect(rows(entries, clock)).toEqual([day('Yesterday'), bubble('a', true, true), day('Today'), bubble('b', true, true)]);
  });

  it('quick messages from one person are one run', () => {
    const entries = [entry('a', 'sunil', date(23, 10, 0)), entry('b', 'sunil', date(23, 10, 2)),
      entry('c', 'sunil', date(23, 10, 4)), entry('d', 'me', date(23, 10, 5), true)];
    expect(rows(entries, clock)).toEqual([day('Today'), bubble('a', true, false), bubble('b', false, false),
      bubble('c', false, true), bubble('d', true, true)]);
  });

  it('a long pause starts a new run', () => {
    const entries = [entry('a', 'sunil', date(23, 10, 0)), entry('b', 'sunil', date(23, 10, 6))];
    expect(rows(entries, clock)).toEqual([day('Today'), bubble('a', true, true), bubble('b', true, true)]);
  });

  it('exactly five minutes is still one run', () => {
    const entries = [entry('a', 'sunil', date(23, 10, 0)), entry('b', 'sunil', date(23, 10, 5))];
    expect(rows(entries, clock)).toEqual([day('Today'), bubble('a', true, false), bubble('b', false, true)]);
  });

  it('midnight splits a run', () => {
    const entries = [entry('a', 'sunil', date(22, 23, 59)), entry('b', 'sunil', date(23, 0, 1))];
    expect(rows(entries, clock)).toEqual([day('Yesterday'), bubble('a', true, true), day('Today'), bubble('b', true, true)]);
  });

  it('midnight is the zone\'s midnight, not UTC\'s', () => {
    // 7:59 pm and 8:01 pm in New York straddle midnight UTC: one day, one run
    const entries = [entry('a', 'sunil', date(22, 19, 59)), entry('b', 'sunil', date(22, 20, 1))];
    expect(rows(entries, clock)).toEqual([day('Yesterday'), bubble('a', true, false), bubble('b', false, true)]);
  });

  it('a message with no date still shows', () => {
    const entries = [entry('a', 'sunil', null), entry('b', 'sunil', null)];
    expect(rows(entries, clock)).toEqual([bubble('a', true, false), bubble('b', false, true)]);
  });
});

describe('dayTitle', () => {
  it('today, yesterday, the weekday, then the date', () => {
    expect(dayTitle(date(23, 1), clock)).toBe('Today');
    expect(dayTitle(date(22, 23), clock)).toBe('Yesterday');
    expect(dayTitle(date(19, 8), clock)).toBe('Thursday');
    expect(dayTitle(date(17, 8), clock)).toBe('Tuesday');
    expect(dayTitle(date(16, 8), clock)).toBe('Mon, Nov 16');
    expect(dayTitle(date(3, 8), clock)).toBe('Tue, Nov 3');
    expect(dayTitle(date(3, 8, 0, 11, 2025), clock)).toBe('Nov 3, 2025');
  });
});

describe('receipt', () => {
  it('sits under your newest message only', () => {
    const mineLast = [entry('a', 'sunil', date(23, 9)), entry('b', 'me', date(23, 10), true)];
    expect(receipt(mineLast)).toEqual({ id: 'b', text: 'Sent' });
    expect(receipt([entry('b', 'me', date(23, 10), true, true)])).toEqual({ id: 'b', text: 'Read' });
    // They answered: no word under the older message
    expect(receipt([entry('b', 'me', date(23, 10), true, true), entry('c', 'sunil', date(23, 11))])).toBeNull();
    expect(receipt([])).toBeNull();
  });
});

describe('timeLabel and dateOf', () => {
  it('formats the time in the zone', () => {
    expect(timeLabel(date(23, 10, 5), clock).replace(/\s/g, ' ')).toBe('10:05 AM');
    expect(timeLabel(null, clock)).toBe('');
  });
  it('reads ISO text and refuses rubbish', () => {
    expect(dateOf('2026-11-23T15:00:00.000Z')?.getTime()).toBe(Date.UTC(2026, 10, 23, 15));
    expect(dateOf('nope')).toBeNull();
    expect(dateOf(null)).toBeNull();
  });
});
