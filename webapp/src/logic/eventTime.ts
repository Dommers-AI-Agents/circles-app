// When an event is, in words. Events carry the venue's own wall-clock date
// and time as strings ("2026-11-28", "19:00:00"); they are read by their
// parts and never through `new Date('2026-11-28')`, which is midnight UTC
// and lands on the day before in US time zones. Pure.

const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

interface Day { y: number; m: number; d: number }

function dayOf(key: string | null | undefined): Day | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(key || ''));
  if (!match) return null;
  const day = { y: Number(match[1]), m: Number(match[2]), d: Number(match[3]) };
  return day.m >= 1 && day.m <= 12 && day.d >= 1 && day.d <= 31 ? day : null;
}

/** Days since 1970 for a calendar day (the same in every time zone). */
const dayNumber = (day: Day): number => Math.round(Date.UTC(day.y, day.m - 1, day.d) / 86400000);

/** This device's calendar day as "YYYY-MM-DD". */
export function localDayKey(now: Date = new Date()): string {
  const pad = (n: number) => (n < 10 ? `0${n}` : String(n));
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** "19:00:00" → "7:00 PM"; "" when there is no time. */
export function timeText(localTime: string | null | undefined): string {
  const match = /^(\d{1,2}):(\d{2})/.exec(String(localTime || ''));
  if (!match) return '';
  const hour = Number(match[1]);
  if (hour > 23) return '';
  return `${hour % 12 === 0 ? 12 : hour % 12}:${match[2]} ${hour < 12 ? 'AM' : 'PM'}`;
}

/** "Fri, Nov 28" (with the year when it isn't this one). */
export function dayText(localDate: string | null | undefined, todayKey: string): string {
  const day = dayOf(localDate);
  if (!day) return '';
  const today = dayOf(todayKey);
  const weekday = DAYS[new Date(Date.UTC(day.y, day.m - 1, day.d)).getUTCDay()];
  const text = `${weekday}, ${MONTHS[day.m - 1]} ${day.d}`;
  return today && today.y !== day.y ? `${text}, ${day.y}` : text;
}

/** "Today 7:00 PM", "Tomorrow", "Fri, Nov 28 · 7:00 PM" */
export function eventWhen(localDate: string | null | undefined, localTime: string | null | undefined, todayKey: string): string {
  const day = dayOf(localDate);
  if (!day) return '';
  const today = dayOf(todayKey);
  const time = timeText(localTime);
  const apart = today ? dayNumber(day) - dayNumber(today) : NaN;
  if (apart === 0) return time ? `Today ${time}` : 'Today';
  if (apart === 1) return time ? `Tomorrow ${time}` : 'Tomorrow';
  const text = dayText(localDate, todayKey);
  return time ? `${text} · ${time}` : text;
}

const money = (amount: number, currency?: string | null): string => {
  const whole = Number.isInteger(amount) ? String(amount) : amount.toFixed(2);
  return !currency || currency === 'USD' ? `$${whole}` : `${whole} ${currency}`;
};

/** "Free", "$25", "$25–$80"; "" when the source doesn't say. */
export function priceText(event: { isFree?: boolean | null; priceMin?: number | null; priceMax?: number | null; currency?: string | null }): string {
  if (event.isFree === true) return 'Free';
  const min = typeof event.priceMin === 'number' && event.priceMin > 0 ? event.priceMin : null;
  const max = typeof event.priceMax === 'number' && event.priceMax > 0 ? event.priceMax : null;
  if (min !== null && max !== null && max > min) return `${money(min, event.currency)}–${money(max, event.currency)}`;
  if (min !== null) return money(min, event.currency);
  if (max !== null) return money(max, event.currency);
  return '';
}

/** A moment (an ISO timestamp) as this device's day: "Nov 28" or "Nov 28, 2025". */
export function stampDay(iso: string | null | undefined, now: Date = new Date()): string {
  const at = new Date(String(iso || ''));
  if (Number.isNaN(at.getTime())) return '';
  const text = `${MONTHS[at.getMonth()]} ${at.getDate()}`;
  return at.getFullYear() === now.getFullYear() ? text : `${text}, ${at.getFullYear()}`;
}

/** "Ends Dec 5" / "Ended Nov 1"; "" for a coupon with no end. */
export function endsLine(expiresAt: string | null | undefined, now: Date = new Date()): string {
  const at = new Date(String(expiresAt || ''));
  if (Number.isNaN(at.getTime())) return '';
  return `${at.getTime() < now.getTime() ? 'Ended' : 'Ends'} ${stampDay(expiresAt, now)}`;
}
