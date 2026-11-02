// When/where/what for events (Evite-style invites, 2026-11-02): validation,
// the time said in the event's own zone, the day-before reminder, calendar.
const d = require('../eventDetails');

const START = '2026-11-08T00:00:00.000Z'; // Sat Nov 7, 7:00 PM in New York (EST)

test('only the fields sent come back, validated', () => {
  expect(d.parseEventDetails({})).toEqual({});
  const out = d.parseEventDetails({ startsAt: START, timezone: 'America/New_York', details: '  Bring a coat  ' }, {}, );
  expect(out.startsAt).toBe(START);
  expect(out.timezone).toBe('America/New_York');
  expect(out.details).toBe('Bring a coat');
  expect(d.parseEventDetails({ timezone: 'Mars/Olympus' }).timezone).toBe('America/New_York');
  expect(d.parseEventDetails({ startsAt: null }).startsAt).toBeNull();
});

test('ends after it starts, within two weeks, and never without a start', () => {
  expect(() => d.parseEventDetails({ startsAt: START, endsAt: START })).toThrow(/after the start/);
  expect(() => d.parseEventDetails({ endsAt: START })).toThrow(/start time/);
  expect(() => d.parseEventDetails({ startsAt: START, endsAt: '2026-12-01T00:00:00Z' })).toThrow(/two weeks/);
  expect(() => d.parseEventDetails({ startsAt: 'next friday' })).toThrow(/real date/);
  // An end checked against the stored start
  expect(() => d.parseEventDetails({ endsAt: '2026-11-07T23:00:00Z' }, { startsAt: START })).toThrow(/after the start/);
});

test('a start gets a zone and the day-before reminder', () => {
  const out = d.parseEventDetails({ startsAt: '2099-01-02T00:00:00Z' });
  expect(out.timezone).toBe('America/New_York');
  expect(out.reminderAt).toBe('2099-01-01T00:00:00.000Z');
  expect(d.reminderAtFor('2026-01-01T10:00:00Z', Date.parse('2026-01-01T00:00:00Z'))).toBeNull();
  expect(d.reminderAtFor(null)).toBeNull();
});

test('a location needs a name or address; a spot only when real', () => {
  expect(d.parseLocation({ name: '', address: '' })).toBeNull();
  expect(d.parseLocation(null)).toBeNull();
  expect(d.parseLocation({ address: '1 Main St' })).toEqual({ name: '1 Main St', address: '1 Main St', lat: null, lng: null });
  expect(d.parseLocation({ name: 'Pasta', lat: 35.2, lng: -80.8 })).toEqual({ name: 'Pasta', address: '', lat: 35.2, lng: -80.8 });
  expect(d.parseLocation({ name: 'Pasta', lat: 'x', lng: 1 }).lat).toBeNull();
});

test('the time is said in the event\'s zone', () => {
  const event = { startsAt: START, timezone: 'America/New_York' };
  expect(d.whenLine(event)).toBe('Saturday, November 7 · 7:00 PM EST');
  expect(d.whenLine({ ...event, endsAt: '2026-11-08T04:00:00.000Z' })).toBe('Saturday, November 7 · 7:00 PM – 11:00 PM EST');
  expect(d.whenLine({ ...event, timezone: 'America/Los_Angeles' })).toBe('Saturday, November 7 · 4:00 PM PST');
  expect(d.whenLine({})).toBeNull();
});

test('where, maps and calendars', () => {
  const event = { id: 'e1', name: 'Bday', emoji: '🎂', startsAt: START, timezone: 'America/New_York',
    location: { name: 'Pasta & Provisions', address: '1528 Central Ave', lat: 35.2, lng: -80.8 }, details: 'Bring, a gift; please' };
  expect(d.whereLine(event)).toBe('Pasta & Provisions, 1528 Central Ave');
  expect(d.mapsUrl(event)).toContain('ll=35.2,-80.8');
  const ics = d.icsFor('e1', event, { url: 'https://x/rsvp/t' });
  expect(ics).toContain('DTSTART:20261108T000000Z');
  expect(ics).toContain('DTEND:20261108T020000Z'); // two hours when there's no end
  expect(ics).toContain('LOCATION:Pasta & Provisions\\, 1528 Central Ave');
  expect(ics).toContain('DESCRIPTION:Bring\\, a gift\\; please');
  expect(ics.split('\r\n').every((line) => Buffer.byteLength(line, 'utf8') <= 75)).toBe(true);
  expect(d.googleCalendarUrl(event)).toContain('dates=20261108T000000Z%2F20261108T020000Z');
  expect(d.icsFor('e1', { name: 'x' })).toBeNull();
});
