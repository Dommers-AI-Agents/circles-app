// backend/services/eventDetails.js
//
// When and where an event happens, and what it's about (Wes, 2026-11-02:
// "email invites and RSVP similar to evite.com"). Pure helpers, tested:
// validating what the app sends, saying the time in the event's own zone,
// and the calendar file / links the invite email and reply page offer.
const { ServiceError } = require('../utils/serviceError');
const { clean } = require('../utils/text');
const { FALLBACK_ZONE } = require('../utils/localClock');

const DETAILS_MAX = 2000;
const PLACE_NAME_MAX = 120;
const ADDRESS_MAX = 200;
const MAX_LENGTH_MS = 14 * 24 * 3600 * 1000; // an event runs two weeks at most
const REMINDER_LEAD_MS = 24 * 3600 * 1000;

const validZone = (zone) => {
  if (typeof zone !== 'string' || !zone.trim()) return null;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone.trim() }).format(new Date());
    return zone.trim();
  } catch (e) {
    return null;
  }
};

const isoOrNull = (value, field) => {
  if (value === null || value === undefined || value === '') return null;
  const ms = Date.parse(value);
  if (!Number.isFinite(ms)) throw new ServiceError(400, 'invalid_time', `That ${field} time isn't a real date`);
  return new Date(ms).toISOString();
};

/**
 * The location the app sends: a name and/or address, and a spot when it came
 * from a map search. Null clears it. Pure.
 */
const parseLocation = (raw) => {
  if (raw === null) return null;
  if (!raw || typeof raw !== 'object') return undefined;
  const name = clean(raw.name, PLACE_NAME_MAX);
  const address = clean(raw.address, ADDRESS_MAX);
  if (!name && !address) return null;
  const lat = Number(raw.lat);
  const lng = Number(raw.lng);
  const hasSpot = raw.lat != null && raw.lng != null && Number.isFinite(lat) && Number.isFinite(lng)
    && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
  return { name: name || address, address, lat: hasSpot ? lat : null, lng: hasSpot ? lng : null };
};

/**
 * The detail fields present in a create/update body, validated. Only keys
 * that were sent come back, so an update leaves the rest alone. `current` is
 * the stored event (for checking an end against a start that isn't changing).
 */
const parseEventDetails = (body = {}, current = {}) => {
  const out = {};
  if ('startsAt' in body) out.startsAt = isoOrNull(body.startsAt, 'start');
  if ('endsAt' in body) out.endsAt = isoOrNull(body.endsAt, 'end');
  if ('timezone' in body) out.timezone = validZone(body.timezone) || FALLBACK_ZONE;
  if ('location' in body) {
    const loc = parseLocation(body.location);
    if (loc !== undefined) out.location = loc;
  }
  if ('details' in body) out.details = clean(body.details, DETAILS_MAX);

  const startsAt = 'startsAt' in out ? out.startsAt : current.startsAt || null;
  const endsAt = 'endsAt' in out ? out.endsAt : current.endsAt || null;
  if (endsAt && !startsAt) throw new ServiceError(400, 'invalid_time', 'Pick a start time before an end time');
  if (startsAt && endsAt) {
    const length = Date.parse(endsAt) - Date.parse(startsAt);
    if (length <= 0) throw new ServiceError(400, 'invalid_time', 'The end has to be after the start');
    if (length > MAX_LENGTH_MS) throw new ServiceError(400, 'invalid_time', 'An event can run two weeks at most');
  }
  // A start without a zone gets one, so it can always be said and reminded
  if (out.startsAt && !('timezone' in out) && !current.timezone) out.timezone = FALLBACK_ZONE;
  // The day-before reminder follows the start; none when it's already that close
  if ('startsAt' in out) out.reminderAt = reminderAtFor(out.startsAt);
  return out;
};

/** When the day-before reminder goes out, or null (no start, or under a day away). */
const reminderAtFor = (startsAt, now = Date.now()) => {
  if (!startsAt) return null;
  const at = Date.parse(startsAt) - REMINDER_LEAD_MS;
  return at > now ? new Date(at).toISOString() : null;
};

const fmt = (iso, zone, options) => new Intl.DateTimeFormat('en-US', { timeZone: zone || FALLBACK_ZONE, ...options }).format(new Date(iso));

/**
 * "Saturday, November 8 · 7:00 PM EST", "… · 7:00 – 11:00 PM EST", or with a
 * second date when it ends another day. Null when there's no start. Pure.
 */
const whenLine = (event) => {
  if (!event || !event.startsAt) return null;
  const zone = validZone(event.timezone) || FALLBACK_ZONE;
  const day = fmt(event.startsAt, zone, { weekday: 'long', month: 'long', day: 'numeric' });
  const time = (iso) => fmt(iso, zone, { hour: 'numeric', minute: '2-digit' });
  const zoneName = fmt(event.startsAt, zone, { timeZoneName: 'short' }).split(' ').pop();
  if (!event.endsAt) return `${day} · ${time(event.startsAt)} ${zoneName}`;
  const endDay = fmt(event.endsAt, zone, { weekday: 'long', month: 'long', day: 'numeric' });
  if (endDay === day) return `${day} · ${time(event.startsAt)} – ${time(event.endsAt)} ${zoneName}`;
  return `${day} ${time(event.startsAt)} – ${endDay} ${time(event.endsAt)} ${zoneName}`;
};

/** "Pasta & Provisions, 1528 Central Ave" / just the one that's there. */
const whereLine = (event) => {
  const loc = event && event.location;
  if (!loc) return null;
  if (loc.address && loc.address !== loc.name) return `${loc.name}, ${loc.address}`;
  return loc.name || loc.address || null;
};

/** Apple Maps link for the location (opens Google Maps elsewhere). */
const mapsUrl = (event) => {
  const loc = event && event.location;
  if (!loc) return null;
  if (Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) {
    return `https://maps.apple.com/?ll=${loc.lat},${loc.lng}&q=${encodeURIComponent(loc.name || 'Event')}`;
  }
  return `https://maps.apple.com/?q=${encodeURIComponent(whereLine(event) || '')}`;
};

const icsDate = (iso) => new Date(iso).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsText = (s) => String(s || '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/[,;]/g, (c) => `\\${c}`);
/** RFC 5545 lines fold at 75 octets. */
const fold = (line) => {
  const out = [];
  let rest = line;
  while (Buffer.byteLength(rest, 'utf8') > 75) {
    let cut = 74;
    while (Buffer.byteLength(rest.slice(0, cut), 'utf8') > 74) cut -= 1;
    out.push(rest.slice(0, cut));
    rest = ` ${rest.slice(cut)}`;
  }
  out.push(rest);
  return out.join('\r\n');
};

/**
 * The .ics for "Add to calendar". Times are UTC instants, so every calendar
 * shows them in the reader's own zone. Defaults to two hours when no end.
 */
const icsFor = (eventId, event, { url } = {}) => {
  if (!event || !event.startsAt) return null;
  const end = event.endsAt || new Date(Date.parse(event.startsAt) + 2 * 3600 * 1000).toISOString();
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//FavCircles//Events//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${eventId}@favcircles.com`,
    `DTSTAMP:${icsDate(new Date().toISOString())}`,
    `DTSTART:${icsDate(event.startsAt)}`,
    `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsText(`${event.emoji || ''} ${event.name}`.trim())}`
  ];
  const where = whereLine(event);
  if (where) lines.push(`LOCATION:${icsText(where)}`);
  const description = [event.details, url].filter(Boolean).join('\n\n');
  if (description) lines.push(`DESCRIPTION:${icsText(description)}`);
  if (url) lines.push(`URL:${url}`);
  lines.push('END:VEVENT', 'END:VCALENDAR');
  return `${lines.map(fold).join('\r\n')}\r\n`;
};

/** Google Calendar's "add event" link. */
const googleCalendarUrl = (event) => {
  if (!event || !event.startsAt) return null;
  const end = event.endsAt || new Date(Date.parse(event.startsAt) + 2 * 3600 * 1000).toISOString();
  const params = new URLSearchParams({
    action: 'TEMPLATE',
    text: `${event.emoji || ''} ${event.name}`.trim(),
    dates: `${icsDate(event.startsAt)}/${icsDate(end)}`
  });
  if (event.details) params.set('details', event.details.slice(0, 900));
  const where = whereLine(event);
  if (where) params.set('location', where);
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
};

/** What the app and pages show about when/where (all optional). */
const toClientDetails = (event) => ({
  startsAt: event.startsAt || null,
  endsAt: event.endsAt || null,
  timezone: event.startsAt ? (validZone(event.timezone) || FALLBACK_ZONE) : null,
  location: event.location || null,
  details: event.details || '',
  whenText: whenLine(event),
  whereText: whereLine(event)
});

module.exports = {
  parseEventDetails, parseLocation, reminderAtFor, whenLine, whereLine, mapsUrl, icsFor, googleCalendarUrl,
  toClientDetails, validZone, DETAILS_MAX, REMINDER_LEAD_MS
};
