const { normalizeLibcal } = require('../localEvents/libcal');
const { joinMcld, parseWhen } = require('../localEvents/mcldaz');
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
