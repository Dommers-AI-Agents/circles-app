import { describe, expect, it } from 'vitest';
import { dayText, endsLine, eventWhen, localDayKey, priceText, stampDay, timeText } from './eventTime';

describe('when an event is', () => {
  it('says today and tomorrow, with the time when there is one', () => {
    expect(eventWhen('2026-11-26', '19:00:00', '2026-11-26')).toBe('Today 7:00 PM');
    expect(eventWhen('2026-11-26', null, '2026-11-26')).toBe('Today');
    expect(eventWhen('2026-11-27', '09:30:00', '2026-11-26')).toBe('Tomorrow 9:30 AM');
  });
  it('names the weekday from the date itself, whatever the time zone', () => {
    // 2026-11-28 is a Saturday everywhere; new Date('2026-11-28') would say Friday in the US
    expect(eventWhen('2026-11-28', null, '2026-11-26')).toBe('Sat, Nov 28');
    expect(eventWhen('2026-11-28', '12:00:00', '2026-11-26')).toBe('Sat, Nov 28 · 12:00 PM');
    expect(dayText('2026-11-27', '2026-11-26')).toBe('Fri, Nov 27');
  });
  it('crosses a month and a year', () => {
    expect(eventWhen('2026-12-01', '00:15:00', '2026-11-30')).toBe('Tomorrow 12:15 AM');
    expect(eventWhen('2027-01-02', null, '2026-12-30')).toBe('Sat, Jan 2, 2027');
  });
  it('says nothing for a date it cannot read', () => {
    expect(eventWhen('', '19:00:00', '2026-11-26')).toBe('');
    expect(eventWhen(null, null, '2026-11-26')).toBe('');
    expect(timeText('25:00')).toBe('');
    expect(timeText('07:05')).toBe('7:05 AM');
  });
  it("reads this device's day from its own clock", () => {
    expect(localDayKey(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05');
  });
});

describe('what an event costs', () => {
  it('says free only when the source says so', () => {
    expect(priceText({ isFree: true, priceMin: 0 })).toBe('Free');
    expect(priceText({ isFree: null, priceMin: null })).toBe('');
    expect(priceText({ isFree: false })).toBe('');
  });
  it('shows a price or a range', () => {
    expect(priceText({ priceMin: 25, priceMax: 25, currency: 'USD' })).toBe('$25');
    expect(priceText({ priceMin: 25, priceMax: 80.5, currency: 'USD' })).toBe('$25–$80.50');
    expect(priceText({ priceMin: 30, currency: 'CAD' })).toBe('30 CAD');
  });
});

describe('a coupon or ledger date', () => {
  const now = new Date(2026, 10, 26, 12);
  it('says when a coupon ends or ended', () => {
    expect(endsLine(new Date(2026, 11, 5, 12).toISOString(), now)).toBe('Ends Dec 5');
    expect(endsLine(new Date(2026, 10, 1, 12).toISOString(), now)).toBe('Ended Nov 1');
    expect(endsLine(null, now)).toBe('');
  });
  it('adds the year when it is another one', () => {
    expect(stampDay(new Date(2025, 10, 28, 12).toISOString(), now)).toBe('Nov 28, 2025');
    expect(stampDay('nonsense', now)).toBe('');
  });
});
