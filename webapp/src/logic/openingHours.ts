// "Open now · closes 5:00 PM" / "Closed · opens 9:00 AM" from a venue's week
// of hours: [{ day (0 = Sunday), open "09:00", close "17:00", isClosed }].
// Pure. The clock is the reader's own, as in the iOS app
// (Logic/OpeningHoursFormatter), whose special cases this mirrors:
//   00:00–23:59 (or 00:00–24:00) is open all day, 00:00–00:00 is closed,
//   a close at or before the open runs past midnight into the next day.

export interface HoursRowLike {
  day: number;
  open?: string | null;
  close?: string | null;
  isClosed?: boolean | null;
}

export interface HoursStatus {
  open: boolean;
  /** "Open now · closes 5:00 PM" */
  text: string;
}

const DAY = 1440;
const WEEK = 7 * DAY;
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const SHORT_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** "09:00" → 540; null for anything that isn't a time of day ("24:00" is 1440). */
export function minutesOf(time: string | null | undefined): number | null {
  const match = typeof time === 'string' ? /^(\d{1,2}):(\d{2})$/.exec(time.trim()) : null;
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (minutes > 59 || hours > 24 || (hours === 24 && minutes !== 0)) return null;
  return hours * 60 + minutes;
}

/** 540 → "9:00 AM", 0 or 1440 → "12:00 AM" */
export function clockText(minutes: number): string {
  const inDay = ((minutes % DAY) + DAY) % DAY;
  const hour = Math.floor(inDay / 60);
  const minute = inDay % 60;
  const shown = hour % 12 === 0 ? 12 : hour % 12;
  return `${shown}:${String(minute).padStart(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}`;
}

type DayKind = 'closed' | 'allDay' | 'hours' | 'unknown';
interface DayHours { kind: DayKind; open: number; close: number }

/** What one row says about its day. */
export function dayHours(row: HoursRowLike | undefined | null): DayHours {
  const unknown: DayHours = { kind: 'unknown', open: 0, close: 0 };
  if (!row) return unknown;
  if (row.isClosed === true) return { ...unknown, kind: 'closed' };
  const open = minutesOf(row.open);
  const close = minutesOf(row.close);
  if (open === null || close === null) return unknown;
  if (open === 0 && close === 0) return { ...unknown, kind: 'closed' };
  if (open === 0 && close >= DAY - 1) return { kind: 'allDay', open: 0, close: DAY };
  return { kind: 'hours', open, close };
}

/** Every stretch the venue is open, in minutes since Sunday 00:00 (an end may pass the week's end). */
function stretches(rows: HoursRowLike[]): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  rows.forEach((row) => {
    if (!row || !Number.isInteger(row.day) || row.day < 0 || row.day > 6) return;
    const day = dayHours(row);
    if (day.kind !== 'hours' && day.kind !== 'allDay') return;
    const start = row.day * DAY + day.open;
    // Closing at or before opening means the small hours of the next day
    const end = row.day * DAY + (day.close > day.open ? day.close : day.close + DAY);
    out.push({ start, end });
  });
  return out;
}

const rowsOf = (hours: readonly HoursRowLike[] | null | undefined): HoursRowLike[] =>
  Array.isArray(hours) ? hours.filter((row) => !!row && typeof row.day === 'number') : [];

/**
 * Open or closed right now, and when that changes. null when the hours say
 * nothing about today (no data is not "closed").
 */
export function hoursStatus(hours: readonly HoursRowLike[] | null | undefined, now: Date): HoursStatus | null {
  const rows = rowsOf(hours);
  if (rows.length === 0) return null;
  const today = now.getDay();
  const minute = today * DAY + now.getHours() * 60 + now.getMinutes();
  const open = stretches(rows);
  // When the stretch covering minute `at` ends (later than `at`), or null.
  // A stretch that began late Saturday can still be running early Sunday.
  const endOf = (at: number): number | null => {
    const inWeek = at % WEEK;
    const base = at - inWeek;
    let end: number | null = null;
    open.forEach((s) => {
      let candidate: number | null = null;
      if (s.start <= inWeek && inWeek < s.end) candidate = base + s.end;
      else if (s.start <= inWeek + WEEK && inWeek + WEEK < s.end) candidate = base + s.end - WEEK;
      if (candidate !== null && (end === null || candidate > end)) end = candidate;
    });
    return end;
  };

  let end = endOf(minute);
  if (end !== null) {
    // Follow back-to-back stretches (open all day, several days running)
    while (end - minute < WEEK) {
      const next = endOf(end);
      if (next === null) break;
      end = next;
    }
    if (end - minute >= WEEK) return { open: true, text: 'Open now · open 24 hours' };
    if (end - minute >= DAY) return { open: true, text: 'Open now · open 24 hours today' };
    return { open: true, text: `Open now · closes ${clockText(end)}` };
  }

  // Closed. Only say so when today's row says something.
  if (dayHours(rows.find((row) => row.day === today)).kind === 'unknown') return null;
  let wait = Infinity;
  open.forEach((s) => {
    const until = (((s.start - minute) % WEEK) + WEEK) % WEEK;
    if (until > 0 && until < wait) wait = until;
  });
  if (!Number.isFinite(wait)) return { open: false, text: 'Closed' };
  const opensAt = minute + wait;
  const daysAhead = Math.floor(opensAt / DAY) - today;
  const time = clockText(opensAt);
  if (daysAhead === 0) return { open: false, text: `Closed · opens ${time}` };
  if (daysAhead === 1) return { open: false, text: `Closed · opens tomorrow at ${time}` };
  return { open: false, text: `Closed · opens ${DAY_NAMES[Math.floor(opensAt / DAY) % 7]} at ${time}` };
}

export interface WeekRow { day: number; name: string; text: string; today: boolean }

/** The week, starting today. Empty when no day has anything to say. */
export function weekRows(hours: readonly HoursRowLike[] | null | undefined, now: Date): WeekRow[] {
  const rows = rowsOf(hours);
  const today = now.getDay();
  const week: WeekRow[] = [];
  let known = 0;
  for (let offset = 0; offset < 7; offset++) {
    const day = (today + offset) % 7;
    const parts = rows.filter((row) => row.day === day).map(dayHours);
    const stretchesToday = parts.filter((p) => p.kind === 'hours').sort((a, b) => a.open - b.open);
    let text = 'Not listed';
    if (parts.some((p) => p.kind === 'allDay')) text = 'Open 24 hours';
    else if (stretchesToday.length > 0) text = stretchesToday.map((p) => `${clockText(p.open)} – ${clockText(p.close)}`).join(', ');
    else if (parts.some((p) => p.kind === 'closed')) text = 'Closed';
    if (text !== 'Not listed') known += 1;
    week.push({ day, name: SHORT_NAMES[day], text, today: offset === 0 });
  }
  return known > 0 ? week : [];
}
