// The user's wall clock, in the user's own zone.
//
// Cloud Run runs in UTC, so any rule written against `new Date().getHours()`
// quietly means "the UTC hour" — which is not the hour the user picked in
// Settings. Quiet hours were enforced that way for a long time: an Eastern
// user who asked for 22:00–08:00 actually got silence from 18:00 to 04:00
// their time, losing every notification through their evening and getting
// woken at 4am instead.
//
// Anything comparing "now" against a time a user chose goes through here.
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// Matches the historical noon-ET behaviour of the summary jobs, so a user
// with no timezone on record keeps the treatment they have always had.
const FALLBACK_ZONE = 'America/New_York';

/**
 * @returns {{hour:number, minute:number, weekday:number, minutes:number}}
 *   weekday is 0=Sunday; `minutes` is minutes since local midnight, which is
 *   what window comparisons want.
 */
const localClock = (timeZone, now = new Date()) => {
  const read = (zone) => {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: zone,
      hour: 'numeric',
      minute: 'numeric',
      hour12: false,
      weekday: 'short'
    }).formatToParts(now);
    const hour = parseInt(parts.find((p) => p.type === 'hour').value, 10) % 24;
    const minute = parseInt(parts.find((p) => p.type === 'minute').value, 10);
    const weekday = WEEKDAYS.indexOf(parts.find((p) => p.type === 'weekday').value);
    return { hour, minute, weekday, minutes: hour * 60 + minute };
  };
  try {
    return read(timeZone || FALLBACK_ZONE);
  } catch (error) {
    // An unknown or malformed zone must not silence a user forever.
    return read(FALLBACK_ZONE);
  }
};

/** "2026-09-19" in the given zone (the user's calendar day, not the server's). */
const localDateKey = (timeZone, now = new Date()) => {
  const read = (zone) => {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
    const get = (type) => parts.find((p) => p.type === type).value;
    return `${get('year')}-${get('month')}-${get('day')}`;
  };
  try { return read(timeZone || FALLBACK_ZONE); } catch (error) { return read(FALLBACK_ZONE); }
};

/** Minutes the zone is ahead of UTC at `date` (−240 for New York in summer). */
const zoneOffsetMinutes = (timeZone, date) => {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit'
  }).formatToParts(date);
  const get = (type) => parseInt(parts.find((p) => p.type === type).value, 10);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour') % 24, get('minute'), get('second'));
  return Math.round((asUtc - date.getTime()) / 60000);
};

/**
 * The instant a wall-clock time happens in a zone: "2026-11-07" + "07:00" in
 * America/New_York → 12:00Z (after the clocks go back), "2026-10-31" → 11:00Z.
 * Never adds days in milliseconds, so weekly times stay put across DST.
 * A time that doesn't exist (the spring-forward hour) resolves to a nearby real instant.
 */
const zonedTimeToUtc = (dateKey, hhmm, timeZone) => {
  const [y, m, d] = String(dateKey).split('-').map((n) => parseInt(n, 10));
  const [h, mi] = String(hhmm).split(':').map((n) => parseInt(n, 10));
  const wall = Date.UTC(y, m - 1, d, h, mi);
  const zone = (() => { try { zoneOffsetMinutes(timeZone, new Date()); return timeZone; } catch (e) { return FALLBACK_ZONE; } })();
  let utc = wall - zoneOffsetMinutes(zone, new Date(wall)) * 60000;
  const again = wall - zoneOffsetMinutes(zone, new Date(utc)) * 60000;
  if (again !== utc) utc = again;
  return new Date(utc);
};

module.exports = { localClock, localDateKey, zonedTimeToUtc, zoneOffsetMinutes, FALLBACK_ZONE };
