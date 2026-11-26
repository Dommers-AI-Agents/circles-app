// What a chat shows, top to bottom: day dividers between days, and messages
// from one person in quick succession drawn as one run (name once at the
// top, avatar and time once at the bottom). A port of the iOS rules,
// ios/Circles-iOS-UIKit/Logic/ChatTimeline.swift, with the same tests.

export interface Entry {
  id: string;
  senderId: string;
  date: Date | null;
  isMine: boolean;
  /** The other person in a one-on-one chat has read it */
  readByOther?: boolean;
}

export type Row =
  | { kind: 'day'; title: string }
  /** startsRun: the sender's name goes here in a group chat. endsRun: the avatar, the time and the bubble's tail go here. */
  | { kind: 'message'; id: string; startsRun: boolean; endsRun: boolean };

export interface Clock {
  /** IANA zone; the browser's own when left out */
  timeZone?: string;
  now?: Date;
  locale?: string;
}

/** Longer than this between two messages from one person starts a new run */
export const RUN_GAP_MS = 5 * 60 * 1000;

const partsFormatters = new Map<string, Intl.DateTimeFormat>();
/** The calendar day a moment falls on in a zone, as a count of days (so days can be subtracted) */
export function dayNumber(date: Date, timeZone?: string): number {
  const key = timeZone || '';
  let formatter = partsFormatters.get(key);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric', month: 'numeric', day: 'numeric' });
    partsFormatters.set(key, formatter);
  }
  let year = 0; let month = 1; let day = 1;
  for (const part of formatter.formatToParts(date)) {
    if (part.type === 'year') year = Number(part.value);
    else if (part.type === 'month') month = Number(part.value);
    else if (part.type === 'day') day = Number(part.value);
  }
  return Math.round(Date.UTC(year, month - 1, day) / 86_400_000);
}

const yearOf = (date: Date, timeZone?: string): number =>
  Number(new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric' }).format(date));

const valid = (date: Date | null | undefined): date is Date => !!date && !Number.isNaN(date.getTime());

const sameDay = (a: Date | null | undefined, b: Date, timeZone?: string): boolean =>
  valid(a) && dayNumber(a, timeZone) === dayNumber(b, timeZone);

/** `b` follows `a` in one run: same person, same day, close in time */
function continuesRun(a: Entry | undefined, b: Entry | undefined, timeZone?: string): boolean {
  if (!a || !b || a.senderId !== b.senderId) return false;
  if (!valid(a.date) || !valid(b.date)) return true;
  return sameDay(a.date, b.date, timeZone) && Math.abs(b.date.getTime() - a.date.getTime()) <= RUN_GAP_MS;
}

/** "Today", "Yesterday", the weekday within the last week, then the date */
export function dayTitle(date: Date, clock: Clock = {}): string {
  const { timeZone, locale } = clock;
  const now = clock.now || new Date();
  const days = dayNumber(now, timeZone) - dayNumber(date, timeZone);
  if (days === 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days > 0 && days < 7) return new Intl.DateTimeFormat(locale, { timeZone, weekday: 'long' }).format(date);
  if (yearOf(date, timeZone) === yearOf(now, timeZone)) {
    return new Intl.DateTimeFormat(locale, { timeZone, weekday: 'short', month: 'short', day: 'numeric' }).format(date);
  }
  return new Intl.DateTimeFormat(locale, { timeZone, month: 'short', day: 'numeric', year: 'numeric' }).format(date);
}

/**
 * `entries` oldest first. `grouped` off is the classic chat: one row per
 * message, each its own run, no day dividers.
 */
export function rows(entries: Entry[], options: Clock & { grouped?: boolean } = {}): Row[] {
  if (options.grouped === false) {
    return entries.map((entry) => ({ kind: 'message', id: entry.id, startsRun: true, endsRun: true }));
  }
  const { timeZone } = options;
  const out: Row[] = [];
  entries.forEach((entry, index) => {
    const previous = index > 0 ? entries[index - 1] : undefined;
    const next = index + 1 < entries.length ? entries[index + 1] : undefined;
    if (valid(entry.date) && !sameDay(previous?.date, entry.date, timeZone)) {
      out.push({ kind: 'day', title: dayTitle(entry.date, options) });
    }
    out.push({
      kind: 'message',
      id: entry.id,
      startsRun: !continuesRun(previous, entry, timeZone),
      endsRun: !continuesRun(entry, next, timeZone)
    });
  });
  return out;
}

/**
 * "Read" or "Sent" under your newest message in a one-on-one chat, and only
 * while it is the last thing said.
 */
export function receipt(entries: Entry[]): { id: string; text: 'Read' | 'Sent' } | null {
  const last = entries[entries.length - 1];
  if (!last || !last.isMine) return null;
  return { id: last.id, text: last.readByOther ? 'Read' : 'Sent' };
}

/** "10:05 AM": the time under the end of a run */
export function timeLabel(date: Date | null, clock: Clock = {}): string {
  if (!valid(date)) return '';
  return new Intl.DateTimeFormat(clock.locale, { timeZone: clock.timeZone, hour: 'numeric', minute: '2-digit' }).format(date);
}

/** A server timestamp (ISO text) as a Date; null when missing or unreadable */
export function dateOf(value: string | null | undefined): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}
