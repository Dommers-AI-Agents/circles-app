// The Locals tab's event search (Wes, 2026-11-04: "Panthers football").
const mockStore = new Map();
const mockDb = {
  collection: () => ({
    doc: (id) => ({
      get: async () => ({ exists: mockStore.has(id), data: () => mockStore.get(id) }),
      set: async (data) => { mockStore.set(id, data); }
    })
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('../liveVenues', () => ({ listLiveVenues: jest.fn(async () => []) }));
jest.mock('../localEvents/library', () => ({ eventsNear: jest.fn(async () => []) }));

const service = require('../nearbyEventsService');
const ticketmaster = require('../localEvents/ticketmaster');
const { _memory } = require('../localEvents/cache');

const CLT = { lat: 35.2271, lng: -80.8431 };
const NOW = new Date('2026-11-04T15:00:00Z');

const tm = (id, name, localDate, extra = {}) => ({
  id, name, url: `https://www.ticketmaster.com/event/${id}`,
  dates: { start: { localDate, localTime: '13:00:00', dateTime: `${localDate}T18:00:00Z` }, status: { code: 'onsale' } },
  classifications: [extra.upsell
    ? { segment: { name: 'Miscellaneous' }, genre: { name: 'Undefined' }, type: { name: 'Upsell' } }
    : { segment: { name: 'Sports' }, genre: { name: 'Football' }, type: { name: 'Group' } }],
  _embedded: { venues: [{ name: 'Bank of America Stadium', city: { name: extra.city || 'Charlotte' },
    location: { latitude: String(extra.lat ?? 35.2258), longitude: String(extra.lng ?? -80.8528) } }] }
});
const answer = (events) => ({ ok: true, json: async () => ({ _embedded: { events } }) });

beforeEach(() => {
  mockStore.clear();
  _memory.clear();
  global.fetch = jest.fn();
  process.env.TICKETMASTER_API_KEY = 'k'.repeat(32);
});

describe('matchesQuery', () => {
  const event = { name: 'Carolina Panthers v Denver Broncos', venueName: 'Bank of America Stadium', category: 'Football', city: 'Charlotte' };
  test('every word, anywhere on the event, any case', () => {
    expect(service.matchesQuery(event, 'panthers football')).toBe(true);
    expect(service.matchesQuery(event, 'Bank Panthers')).toBe(true);
    expect(service.matchesQuery(event, 'panthers hockey')).toBe(false);
    expect(service.matchesQuery(event, '  ')).toBe(false);
  });
});

describe('searchLocalEvents', () => {
  test('Ticketmaster rows near you, soonest first, add-ons dropped', async () => {
    global.fetch.mockResolvedValue(answer([
      tm('b', 'Carolina Panthers v Baltimore Ravens', '2026-11-22'),
      tm('x', 'Reserve Access (Not A Game Ticket) - Broncos at Panthers', '2026-11-08', { upsell: true }),
      tm('a', 'Carolina Panthers v Denver Broncos', '2026-11-08')
    ]));
    const out = await service.searchLocalEvents('Panthers football', CLT.lat, CLT.lng, { now: NOW });
    expect(out.events.map((e) => e.id)).toEqual(['tm_a', 'tm_b']);
    expect(out.nearby).toBe(true);
    expect(out.events[0].distanceMeters).toBeGreaterThan(0);
    expect(out.attribution).toBe('Events from Ticketmaster');
    const url = new URL(global.fetch.mock.calls[0][0]);
    expect(url.searchParams.get('keyword')).toBe('panthers football');
    expect(url.searchParams.get('radius')).toBe('100');
  });

  test('nothing within reach: the same search anywhere, marked not nearby', async () => {
    global.fetch
      .mockResolvedValueOnce(answer([]))
      .mockResolvedValueOnce(answer([tm('z', 'Florida Panthers vs. Boston Bruins', '2026-11-10', { city: 'Sunrise', lat: 26.158, lng: -80.325 })]));
    const out = await service.searchLocalEvents('florida panthers', CLT.lat, CLT.lng, { now: NOW });
    expect(out.events.map((e) => e.id)).toEqual(['tm_z']);
    expect(out.nearby).toBe(false);
    expect(new URL(global.fetch.mock.calls[1][0]).searchParams.get('latlong')).toBeNull();
  });

  test('the same words again are served from the cache', async () => {
    global.fetch.mockResolvedValue(answer([tm('a', 'Carolina Panthers v Denver Broncos', '2026-11-08')]));
    await service.searchLocalEvents('Panthers', CLT.lat, CLT.lng, { now: NOW });
    await service.searchLocalEvents('  panthers ', CLT.lat, CLT.lng, { now: NOW });
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('one letter, or Ticketmaster down: an empty answer, never a throw', async () => {
    expect((await service.searchLocalEvents('p', CLT.lat, CLT.lng, { now: NOW })).events).toEqual([]);
    global.fetch.mockResolvedValue({ ok: false, status: 500, json: async () => ({}) });
    const out = await service.searchLocalEvents('panthers', CLT.lat, CLT.lng, { now: NOW });
    expect(out.events).toEqual([]);
  });

  test('a matching store event on FavCircles leads', async () => {
    require('../liveVenues').listLiveVenues.mockResolvedValueOnce([{
      venueId: 'v1', venueName: 'Sal\'s', location: { lat: 35.22, lng: -80.84 }, globalPlaceId: 'g1',
      announcements: [{ announcementId: 'a1', title: 'Panthers watch party', isActive: true,
        event: { startsAt: '2026-11-09T18:00:00Z', localDate: '2026-11-09', localTime: '13:00' } }]
    }]);
    global.fetch.mockResolvedValue(answer([tm('a', 'Carolina Panthers v Denver Broncos', '2026-11-08')]));
    const out = await service.searchLocalEvents('panthers', CLT.lat, CLT.lng, { now: NOW });
    expect(out.events[0].id).toBe('store_v1_a1');
  });
});
