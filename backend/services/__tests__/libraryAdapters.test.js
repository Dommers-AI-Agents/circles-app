const { normalizeLibcal } = require('../localEvents/libcal');
const { joinMcld, parseWhen } = require('../localEvents/mcldaz');
const { normalizeCommunico } = require('../localEvents/communico');
const { normalizeLibraryMarket } = require('../localEvents/librarymarket');
const { matchBranch, zonedToUtc } = require('../localEvents/libraryCommon');

const branches = [
  { name: 'Wall Township', match: ['Wall Township'], lat: 40.15, lng: -74.07 },
  { name: 'West Long Branch', match: ['West Long Branch'], lat: 40.29, lng: -74.01 },
  { name: 'Century', match: ['Century'], lat: 33.5, lng: -112.04 },
  { name: 'Perry', match: ['Perry'], lat: 33.26, lng: -111.74 }
];
const window = { fromDay: '2026-10-15', toDay: '2026-10-18' };

test('local time to UTC, with and without daylight saving', () => {
  expect(zonedToUtc('2026-10-17', '19:00:00', 'America/New_York')).toBe('2026-10-17T23:00:00.000Z');
  expect(zonedToUtc('2026-12-17', '19:00:00', 'America/New_York')).toBe('2026-12-18T00:00:00.000Z');
  expect(zonedToUtc('2026-10-17', '19:00:00', 'America/Phoenix')).toBe('2026-10-18T02:00:00.000Z');
});

test('branch matching prefers the longest name', () => {
  expect(matchBranch('Meeting Room, West Long Branch', branches).name).toBe('West Long Branch');
  expect(matchBranch('Zoom Room', branches)).toBeNull();
});

describe('LibCal', () => {
  const feed = { host: 'x.libcal.com', name: 'Monmouth County Library', timeZone: 'America/New_York', branches };
  const raw = (id, title, startdt, location, extra = {}) => ({
    id, title, startdt, location, all_day: 'False', online_event: 'False', registration_cost: '', url: `https://x.libcal.com/event/${id}`, ...extra
  });

  test('timed programs we can place, in the window', () => {
    const events = normalizeLibcal({ results: [
      raw(1, 'Book Club', '2026-10-15 15:00:00', 'Wall Township Branch'),
      raw(2, 'On Display: Student Art', '2026-10-15 09:00:00', 'Wall Township Branch'),
      raw(3, 'StoryWalk at the Park', '2026-10-16 00:00:00', 'Wall Township Branch'),
      raw(4, 'Webinar', '2026-10-15 12:00:00', 'Zoom Room', { online_event: 'True' }),
      raw(5, 'Later', '2026-11-20 10:00:00', 'Wall Township Branch'),
      raw(6, '21st Century Skills', '2026-10-15 10:00:00', 'Room 4, Room 5'),
      raw(7, 'Concert', '2026-10-16 14:00:00', 'Lower Gallery, West Long Branch', { registration_cost: '$10', featured_image: 'https://img/c.png' })
    ] }, feed, window);
    expect(events.map((e) => e.name)).toEqual(['Book Club', 'Concert']);
    expect(events[0]).toMatchObject({ source: 'library', venueName: 'Wall Township Library', isFree: true, startUtc: '2026-10-15T19:00:00.000Z', lat: 40.15 });
    expect(events[1]).toMatchObject({ isFree: null, imageUrl: 'https://img/c.png', venueName: 'West Long Branch Library' });
  });
});

describe('Maricopa County Library District', () => {
  const feed = { host: 'events.mcldaz.org', name: 'Maricopa County Library District', timeZone: 'America/Phoenix', branches };
  const item = (id, title, when) => `<item><title>${title}</title><link>https://events.mcldaz.org/event?id=${id}</link>
    <description>&lt;p&gt;&lt;strong&gt;Date/Time:&lt;/strong&gt; ${when}&lt;/p&gt;&lt;p&gt;Fun for all&lt;/p&gt;</description></item>`;
  const xml = `<rss><channel>${[
    item(1, 'Boo Bash', 'Sat, 17 Oct 2026, 10:00am - 11:00am'),
    item(2, 'Take and Make Crafts', 'Thu, 1 Oct 2026, 9:00am - Sat, 31 Oct 2026, 5:00pm'),
    item(3, 'Mystery spot', 'Fri, 16 Oct 2026, 1:00pm - 2:00pm'),
    item(4, 'Evening Club', 'Fri, 16 Oct 2026, 12:30pm - 1:30pm')
  ].join('')}</channel></rss>`;
  const row = (id, third) => `<tr> <td><a href="event?id=${id}">x</a></td> <td>soon</td> <td>${third}</td> </tr>`;
  const html = [row(1, 'Adult (18+) / Craft'), row(1, 'Perry Library'), row(3, 'All ages'), row(4, 'Perry Library')].join('');

  test('RSS times joined with the list page branches', () => {
    const events = joinMcld(xml, html, feed, window);
    expect(events.map((e) => e.name)).toEqual(['Boo Bash', 'Evening Club']);
    expect(events[0]).toMatchObject({ startLocalDate: '2026-10-17', startLocalTime: '10:00:00', venueName: 'Perry Library', message: 'Fun for all' });
    expect(events[1].startLocalTime).toBe('12:30:00');
  });

  test('times: am/pm, noon, and spans over a day', () => {
    expect(parseWhen('Fri, 16 Oct 2026, 12:30pm - 1:30pm')).toEqual({ date: '2026-10-16', time: '12:30:00' });
    expect(parseWhen('Fri, 16 Oct 2026, 12:05am - 1:30am')).toEqual({ date: '2026-10-16', time: '00:05:00' });
    expect(parseWhen('Thu, 1 Oct 2026, 9:00am - Sat, 31 Oct 2026, 5:00pm')).toBeNull();
  });
});

describe('Communico', () => {
  const feed = {
    host: 'visit.x.org', name: 'LA County Library', timeZone: 'America/Los_Angeles', imageBase: 'https://static/img/',
    branches: [{ name: 'Carson Library', match: ['Carson Library'], lat: 33.83, lng: -118.27 }]
  };
  const raw = (id, title, start, extra = {}) => ({
    id: String(id), title, event_start: start, location: 'Carson Library', event_type: 'INPERSON', venue_type: 'internal',
    private_event: '0', changed: null, registration_cost: '0', recurring_id: '0', url: `https://visit.x.org/event/${id}`, ...extra
  });

  test('in-person programs at a branch we know, in the window', () => {
    const events = normalizeCommunico([
      raw(1, 'Baby Storytime', '2026-10-15 10:30:00', { recurring_id: '77', event_image: 'a b.jpg' }),
      raw(2, 'Online Talk', '2026-10-15 11:00:00', { event_type: 'ONLINE' }),
      raw(3, 'Cancelled Craft', '2026-10-15 12:00:00', { changed: '1' }),
      raw(4, 'Wellness Workshop', '2026-10-15 13:00:00', { sub_title: 'LEAP Support Group' }),
      raw(5, 'Park Day', '2026-10-15 14:00:00', { venue_type: 'external' }),
      raw(6, 'Elsewhere', '2026-10-15 15:00:00', { location: 'Unknown Library' }),
      raw(7, 'Later', '2026-11-20 10:00:00'),
      raw(8, 'Movie Night', '2026-10-16 18:00:00', { registration_cost: '5' })
    ], feed, window);
    expect(events.map((e) => e.name)).toEqual(['Baby Storytime', 'Movie Night']);
    expect(events[0]).toMatchObject({
      id: 'lib_visit.x.org_1', source: 'library', venueName: 'Carson Library', lat: 33.83, isFree: true, seriesId: 'cm_77',
      startUtc: '2026-10-15T17:30:00.000Z', imageUrl: 'https://static/img/a%20b.jpg', url: 'https://visit.x.org/event/1'
    });
    expect(events[1]).toMatchObject({ isFree: null, seriesId: null, imageUrl: null });
    expect(normalizeCommunico({ error: true }, feed, window)).toEqual([]);
  });
});

describe('LibraryMarket', () => {
  const feed = {
    host: 'www.x.org', name: 'Bossier Parish Libraries', timeZone: 'America/Chicago',
    branches: [{ name: 'Aulds', match: ['Aulds Library Branch'], lat: 32.48, lng: -93.67 }]
  };
  const raw = (id, title, start, extra = {}) => ({
    id: String(id), title, start_date: start, timezone: 'America/Chicago', public: true, published: true,
    branch: { 9: 'Aulds Library Branch' }, offsite_address: null, online_address: null, image: null,
    description: '<p>Fun</p>', url: `https://www.x.org/event/e-${id}`, ...extra
  });

  test('public programs at one branch we know, in the window', () => {
    const events = normalizeLibraryMarket([
      raw(1, 'Video Game Club', '2026-10-15 16:00:00', { image: 'https://www.x.org/a.png' }),
      raw(2, 'Storytime at the Park', '2026-10-15 09:00:00', { offsite_address: '1 Park Rd' }),
      raw(3, 'Closed for the holiday', '2026-10-16 09:00:00', { branch: { 9: 'Aulds Library Branch', 8: 'Benton Library Branch' } }),
      raw(4, 'Staff Day', '2026-10-15 10:00:00', { public: false }),
      raw(5, 'Outreach', '2026-10-15 10:00:00', { branch: { 2: 'Community Engagement' } }),
      raw(6, 'Later', '2026-11-20 10:00:00')
    ], feed, window);
    expect(events.map((e) => e.name)).toEqual(['Video Game Club']);
    expect(events[0]).toMatchObject({
      venueName: 'Aulds Library', lat: 32.48, message: 'Fun', startUtc: '2026-10-15T21:00:00.000Z',
      imageUrl: 'https://www.x.org/a.png', isFree: true
    });
  });
});

describe('coverage gaps', () => {
  const mockSet = jest.fn(async () => {});
  jest.doMock('../../config/firebase', () => ({
    getFirestore: () => ({ collection: () => ({ doc: () => ({ set: mockSet }) }) }),
    FieldValue: { increment: (n) => ({ inc: n }) }
  }));
  const gaps = () => jest.requireActual('../localEvents/coverageGaps');
  const NOW = Date.parse('2026-11-23T12:00:00Z');

  test('one count per cell, reason and asker per instance per few hours; no user ids', () => {
    jest.isolateModules(() => {
      const { recordGap } = require('../localEvents/coverageGaps');
      recordGap(32.9778, -111.5177, { now: 1000 });
      recordGap(32.9779, -111.5176, { now: 2000 }); // same cell, too soon
      recordGap(32.9779, -111.5176, { source: 'letter', now: 3000 }); // the weekly letter counts on its own
      recordGap(40.71, -74.0, { reason: 'far', now: 4000 });
      recordGap(40.71, -74.0, { reason: 'bogus', now: 5000 });
      recordGap(32.9779, -111.5176, { source: 'letter', now: 6000 }); // every letter is a person
    });
    expect(mockSet).toHaveBeenCalledTimes(4);
    expect(mockSet.mock.calls[0][0]).toEqual({
      cell: '9tbe', lat: 33, lng: -111.5, days: { '1970-01-01': { tab_none: { inc: 1 } } }, lastSeenAt: new Date(1000).toISOString()
    });
    expect(mockSet.mock.calls[1][0].days).toEqual({ '1970-01-01': { letter_none: { inc: 1 } } });
    expect(mockSet.mock.calls[2][0].days).toEqual({ '1970-01-01': { tab_far: { inc: 1 } } });
  });

  test('counts cover the last 30 days only; old rows keep their running total apart', () => {
    const { countsFor } = gaps();
    const row = { days: {
      '2026-10-01': { tab_none: 9 }, // too old
      '2026-11-10': { tab_none: 2, letter_none: 1 },
      '2026-11-18': { letter_none: 1, tab_empty: 1 },
      '2026-11-20': { letter_empty: 2 }
    } };
    expect(countsFor(row, { now: NOW })).toMatchObject({ tab: 3, letter: 4, none: 4, empty: 3, emptyDays: 2, total: 7, earlier: 0 });
    expect(countsFor({ opens: 6 }, { now: NOW })).toMatchObject({ total: 0, earlier: 6 });
  });

  test('place names: town, state and county; abroad keeps the country', () => {
    const { formatPlace } = gaps();
    expect(formatPlace({ city: 'Casa Grande', county: 'Pinal County', state: 'Arizona', 'ISO3166-2-lvl4': 'US-AZ', country_code: 'us' }))
      .toEqual({ place: 'Casa Grande, AZ (Pinal County)', country: 'us' });
    expect(formatPlace({ county: 'Charlotte County', state: 'Florida', 'ISO3166-2-lvl4': 'US-FL', country_code: 'us' }).place).toBe('Charlotte County, FL');
    expect(formatPlace({ city: 'Puerto Vallarta', state: 'Jalisco', country: 'Mexico', country_code: 'mx' }))
      .toEqual({ place: 'Puerto Vallarta, Jalisco, Mexico', country: 'mx' });
  });

  test('the report: real gaps only, sorted into sections', () => {
    const { classifyGaps, buildReport } = gaps();
    const covered = {
      '33.8,-118.2': [{ name: 'LA County Library', branches: [{ lat: 33.83, lng: -118.27 }] }],
      '32.9,-111.7': [{ name: 'Maricopa County Library District', branches: [{ lat: 33.22, lng: -111.88 }] }],
      '42,-87.9': [{ name: 'Chicago Public Library' }],
      '33.6,-112': [{ name: 'Phoenix Public Library', branches: [{ lat: 33.6, lng: -111.98 }] }]
    };
    const feedsNear = (lat, lng) => covered[`${lat},${lng}`] || [];
    const day = '2026-11-20';
    const sections = classifyGaps([
      { cell: 'a', lat: 32.8, lng: -111.7, place: 'Casa Grande, AZ (Pinal County)', country: 'us', days: { [day]: { letter_none: 4 } } },
      { cell: 'i', lat: 32.9, lng: -111.7, place: 'Casa Grande, AZ (Pinal County)', country: 'us', opens: 6 }, // old row, system near but no branch in reach
      { cell: 'b', lat: 34.2, lng: -110, place: 'Show Low, AZ', country: 'us', days: { [day]: { tab_none: 1 } } },
      { cell: 'c', lat: 37.8, lng: -122.4, place: 'San Francisco, California', opens: 2 }, // before per-day counts
      { cell: 'd', lat: 20.7, lng: -105.3, place: 'Puerto Vallarta, Jalisco, Mexico', country: 'mx', days: { [day]: { letter_none: 2 } } },
      { cell: 'j', lat: 42, lng: -87.9, place: 'Chicago, IL', country: 'us', opens: 1 }, // old row, can't tell: left out
      { cell: 'k', lat: 33.8, lng: -118.2, place: 'Long Beach, CA', country: 'us', days: { [day]: { tab_far: 3 } } }, // far before its system was added
      { cell: 'e', lat: 33.8, lng: -118.2, place: 'Long Beach, CA', country: 'us', opens: 4 }, // old row, a branch is in reach now: not a gap
      { cell: 'f', lat: 42, lng: -87.9, place: 'Park Ridge, IL', country: 'us', days: { [day]: { tab_far: 2 } } },
      { cell: 'g', lat: 33.6, lng: -112, place: 'Phoenix, AZ', country: 'us', days: { [day]: { letter_empty: 1 }, '2026-11-21': { tab_empty: 1 } } },
      { cell: 'h', lat: 1, lng: 1, days: { '2026-09-01': { tab_none: 3 } } } // nothing in the window
    ], { feedsNear, now: NOW });
    expect(sections.none.map((r) => r.cell)).toEqual(['b', 'a', 'c']); // opens first, then letters, then old counts
    expect(sections.far.map((r) => r.cell)).toEqual(['f', 'i']);
    expect(sections.empty.map((r) => r.cell)).toEqual(['g']);
    expect(sections.abroad.map((r) => r.cell)).toEqual(['d']);

    const report = buildReport(sections);
    expect(report.title).toBe('Local tab: 5 places with no library programs in reach');
    expect(report.places).toBe(5);
    expect(report.body).toContain('NO LIBRARY SYSTEM SET UP (3)\n1. Show Low, AZ: 1 open\n2. Casa Grande, AZ (Pinal County): 4 letters\n3. San Francisco, California: 2 earlier');
    expect(report.body).toContain('1. Park Ridge, IL: 2 times\n   nearest: Chicago Public Library\n2. Casa Grande, AZ (Pinal County): 6 earlier\n   nearest: Maricopa County Library District');
    expect(report.body).toContain('1. Phoenix, AZ: 2 days\n   check Phoenix Public Library');
    expect(report.body).toContain('OUTSIDE THE US AND CANADA (1)\n1. Puerto Vallarta, Jalisco, Mexico: 2 letters');
    expect(report.body).not.toContain('Long Beach');

    expect(buildReport({ none: [], far: [], empty: [], abroad: sections.abroad })).toBeNull();
    expect(buildReport({ none: [], far: [], empty: sections.empty, abroad: [] }).title).toBe('Local tab: library calendars to check');
  });
});
