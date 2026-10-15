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
jest.mock('../localEvents/farmersMarkets', () => ({ marketsNear: jest.fn(async () => []) }));

const service = require('../nearbyEventsService');
const ticketmaster = require('../localEvents/ticketmaster');
const library = require('../localEvents/library');
const { storeEventsFrom } = require('../localEvents/storeEvents');
const { normalizeMarket } = jest.requireActual('../localEvents/farmersMarkets');
const { _memory } = require('../localEvents/cache');
const { validateAnnouncementEvent, cleanAnnouncementEvent, eventExpiry } = require('../../models/StickerModels');

const CLT = { lat: 35.2271, lng: -80.8431 };

function tmEvent(overrides = {}) {
  return {
    id: 'e1',
    name: 'Jazz Night',
    url: 'https://www.ticketmaster.com/event/e1',
    dates: { start: { localDate: '2026-10-18', localTime: '20:00:00', dateTime: '2026-10-19T00:00:00Z' }, status: { code: 'onsale' } },
    images: [
      { ratio: '16_9', width: 2048, url: 'big.jpg' },
      { ratio: '16_9', width: 640, url: 'right.jpg' },
      { ratio: '4_3', width: 305, url: 'square.jpg' }
    ],
    classifications: [{ segment: { name: 'Music' }, genre: { name: 'Jazz' } }],
    priceRanges: [{ min: 25, max: 60, currency: 'USD' }],
    _embedded: { venues: [{ name: 'The Fillmore', address: { line1: '820 Hamilton St' }, city: { name: 'Charlotte' }, location: { latitude: '35.2330', longitude: '-80.8460' } }] },
    ...overrides
  };
}

const libPayload = (events, locations = {}) => ({
  events: { results: events.map((e) => e.id), pagination: { pages: 1 } },
  entities: {
    events: Object.fromEntries(events.map((e) => [e.id, e])),
    locations,
    images: { img1: { url: 'https://img/lib.jpg' } }
  }
});
const libEvent = (id, start, title, extra = {}) => ({
  id, seriesId: extra.seriesId || null,
  definition: { start, title, description: extra.description || '<p>Songs &amp; rhymes</p>', branchLocationId: extra.branch || 'b1', featuredImageId: 'img1', isCancelled: !!extra.cancelled },
  indexStart: `${start}:00Z`
});
const branches = {
  b1: { name: 'ImaginOn', address: { number: '300', street: 'East Seventh Street', city: 'Charlotte' }, mapLocation: { centrePoint: { lat: 35.227, lng: -80.8377 } } },
  far: { name: 'Far Branch', address: {}, mapLocation: { centrePoint: { lat: 35.5, lng: -80.8 } } }
};
const feed = { libraryId: 'cmlibrary', name: 'Charlotte Mecklenburg Library' };

beforeEach(() => {
  mockStore.clear();
  _memory.clear();
  global.fetch = jest.fn();
});

describe('Ticketmaster', () => {
  test('normalizes an event: image, category, price, link', () => {
    const [event] = ticketmaster.normalizeEvents({ _embedded: { events: [tmEvent()] } });
    expect(event).toMatchObject({
      id: 'tm_e1', source: 'ticketmaster', name: 'Jazz Night', startLocalTime: '20:00:00',
      venueName: 'The Fillmore', category: 'Jazz', imageUrl: 'right.jpg', priceMin: 25, url: 'https://www.ticketmaster.com/event/e1'
    });
  });

  test('drops cancelled events', () => {
    expect(ticketmaster.normalizeEvents({ _embedded: { events: [tmEvent({ dates: { start: { localDate: '2026-10-17' }, status: { code: 'cancelled' } } })] } })).toEqual([]);
  });

  test('no key → nothing and no request; one fetch per cell per day', async () => {
    expect(await ticketmaster.eventsNear(CLT.lat, CLT.lng, { apiKey: '' })).toEqual([]);
    expect(global.fetch).not.toHaveBeenCalled();
    global.fetch.mockResolvedValue({ ok: true, json: async () => ({ _embedded: { events: [tmEvent()] } }) });
    const now = new Date('2026-10-15T12:00:00Z');
    await ticketmaster.eventsNear(CLT.lat, CLT.lng, { apiKey: 'k', now });
    await ticketmaster.eventsNear(CLT.lat + 0.001, CLT.lng, { apiKey: 'k', now });
    _memory.clear(); // another instance reads Firestore
    await ticketmaster.eventsNear(CLT.lat, CLT.lng, { apiKey: 'k', now });
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  test('upstream failure → empty, and not retried for a few minutes', async () => {
    global.fetch.mockResolvedValue({ ok: false, status: 401, json: async () => ({}) });
    const now = new Date('2026-10-15T12:00:00Z');
    expect(await ticketmaster.eventsNear(CLT.lat, CLT.lng, { apiKey: 'bad', now })).toEqual([]);
    expect(await ticketmaster.eventsNear(CLT.lat, CLT.lng, { apiKey: 'bad', now })).toEqual([]);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});

describe('library programs', () => {
  test('timed, not cancelled, free unless ticketed, with the branch', () => {
    const events = library.normalizePage(libPayload([
      libEvent('a', '2026-10-16T09:30', 'Baby Storytime'),
      libEvent('b', '2026-10-16', 'Book display'),
      libEvent('c', '2026-10-16T10:00', 'Gone', { cancelled: true }),
      libEvent('d', '2026-10-16T15:00', 'The Grinch Musical', { description: '<p>**This is a TICKETED show**</p>' })
    ], branches), feed);
    expect(events.map((e) => e.name)).toEqual(['Baby Storytime', 'The Grinch Musical']);
    expect(events[0]).toMatchObject({
      source: 'library', sourceName: 'Charlotte Mecklenburg Library', startLocalTime: '09:30:00', venueName: 'ImaginOn',
      venueAddress: '300 East Seventh Street', isFree: true, message: 'Songs & rhymes', imageUrl: 'https://img/lib.jpg',
      url: 'https://cmlibrary.bibliocommons.com/events/a'
    });
    expect(events[1].isFree).toBeNull();
  });

  test('a library only serves its own area', () => {
    expect(library.feedsNear(CLT.lat, CLT.lng).map((f) => f.libraryId)).toContain('cmlibrary');
    expect(library.feedsNear(46.8083, -100.7837)).toEqual([]); // Bismarck, ND
  });
});

describe('store events', () => {
  const venue = (announcements, extra = {}) => ({
    venueId: 'v1', venueName: 'Sal’s', placeName: 'Sal’s Pizza', globalPlaceId: 'g1',
    location: { lat: 35.23, lng: -80.84 }, announcements, ...extra
  });
  const now = new Date('2026-10-15T12:00:00Z');
  const ann = (id, event) => ({ announcementId: id, title: `Event ${id}`, message: 'Come by', event, expiresAt: null, createdAt: '2026-10-01' });

  test('upcoming events near you, with a link to the place', () => {
    const events = storeEventsFrom([venue([
      ann('soon', { startsAt: '2026-10-17T23:00:00Z', localDate: '2026-10-17', localTime: '19:00:00', isFree: true }),
      ann('over', { startsAt: '2026-10-14T23:00:00Z', localDate: '2026-10-14', localTime: '19:00:00' }),
      ann('far-future', { startsAt: '2026-12-17T23:00:00Z', localDate: '2026-12-17' }),
      { announcementId: 'plain', title: 'Half off', message: 'x' }
    ])], CLT.lat, CLT.lng, now);
    expect(events.map((e) => e.id)).toEqual(['store_v1_soon']);
    expect(events[0]).toMatchObject({ source: 'store', isFree: true, venueId: 'v1', globalPlaceId: 'g1', url: 'https://api.favcircles.com/place/g1' });
  });

  test('far-away and online-only stores are left out', () => {
    const event = ann('x', { startsAt: '2026-10-17T23:00:00Z', localDate: '2026-10-17' });
    expect(storeEventsFrom([venue([event], { location: { lat: 40.7, lng: -74 } }), venue([event], { isVirtual: true })], CLT.lat, CLT.lng, now)).toEqual([]);
  });

  test('event validation and expiry', () => {
    const future = new Date(Date.now() + 86400000).toISOString();
    expect(validateAnnouncementEvent({ startsAt: future, localDate: '2026-10-17', localTime: '19:00', isFree: true })).toEqual([]);
    expect(validateAnnouncementEvent(null)).toEqual([]);
    expect(validateAnnouncementEvent({ startsAt: 'nope', localDate: 'x' }).length).toBe(2);
    expect(validateAnnouncementEvent({ startsAt: future, endsAt: '2020-01-01T00:00:00Z', localDate: '2026-10-17' })[0]).toMatch(/after it starts/);
    const cleaned = cleanAnnouncementEvent({ startsAt: '2026-10-17T23:00:00Z', localDate: '2026-10-17', localTime: '19:00' });
    expect(cleaned).toEqual({ startsAt: '2026-10-17T23:00:00.000Z', endsAt: null, localDate: '2026-10-17', localTime: '19:00:00', isFree: null });
    expect(eventExpiry(cleaned)).toBe('2026-10-18T03:00:00.000Z');
  });
});

describe('merging', () => {
  const tmRow = (id, date, time, name = id) => ({ id, source: 'ticketmaster', name, venueName: 'V', startLocalDate: date, startLocalTime: time, lat: 35.23, lng: -80.84 });
  const libRow = (id, date, time, name, lat = 35.227, seriesId = null) => ({ id, source: 'library', sourceName: 'Charlotte Mecklenburg Library', seriesId, name, startLocalDate: date, startLocalTime: time, lat, lng: -80.84 });

  test('soonest first, one row per show, library near you only, stores always in', () => {
    const events = service.mergeEvents({
      store: [{ id: 's1', source: 'store', name: 'Trivia', startLocalDate: '2026-10-20', startLocalTime: '19:00:00', lat: 35.23, lng: -80.84 }],
      tm: [tmRow('t2', '2026-10-17', '20:00:00', 'Show'), tmRow('t1', '2026-10-16', '20:00:00', 'Show'), tmRow('t3', '2026-10-16', '19:00:00', 'Other')],
      lib: [
        libRow('l1', '2026-10-16', '09:30:00', 'Baby Storytime', 35.227, 'sA'),
        libRow('l2', '2026-10-17', '09:30:00', 'Baby Storytime', 35.227, 'sA'),
        libRow('l3', '2026-10-16', '10:00:00', 'Far Program', 35.6)
      ]
    }, CLT.lat, CLT.lng);
    expect(events.map((e) => e.id)).toEqual(['l1', 't3', 't1', 's1']);
    expect(events[0].distanceMeters).toBeGreaterThan(0);
    expect(events[0].seriesId).toBeUndefined();
  });

  test('at most three library programs a day', () => {
    const lib = ['a', 'b', 'c', 'd'].map((n, i) => libRow(n, '2026-10-16', `1${i}:00:00`, `Program ${n}`));
    expect(service.mergeEvents({ lib }, CLT.lat, CLT.lng, new Date('2026-10-15T12:00:00Z')).map((e) => e.id)).toEqual(['a', 'b', 'c']);
  });

  test('credits each source once', () => {
    expect(service.attributionFor([{ source: 'ticketmaster' }, { source: 'library', sourceName: 'Charlotte Mecklenburg Library' }], [{}]))
      .toBe('Events from Ticketmaster and Charlotte Mecklenburg Library · Farmers markets from the USDA directory');
    expect(service.attributionFor([{ source: 'store' }], [])).toBeNull();
  });

  test('no location → empty feed', async () => {
    expect(await service.getLocalFeed(NaN, 1)).toEqual({ events: [], markets: [], attribution: null });
  });
});

describe('farmers markets', () => {
  test('directory rows become markets with a geohash; junk rows are skipped', () => {
    const market = normalizeMarket({
      listing_id: '300365', listing_name: 'Charlotte Regional Farmers Market', location_address: '1801 Yorkmont Road, Charlotte',
      location_x: '-80.908718', location_y: '35.1867102', FNAP: 'SNAP;Accept EBT', specialproductionmethods: 'Organic (USDA Certified);',
      location_desc: 'Off   Billy Graham Pkwy', update_time: '2020-09-11 08:14:33'
    });
    expect(market).toMatchObject({ id: '300365', acceptsSnap: true, organic: true, directions: 'Off Billy Graham Pkwy', lat: 35.1867102 });
    expect(market.geohash).toMatch(/^dnq/);
    expect(normalizeMarket({ listing_id: '1', listing_name: 'No place', location_x: '', location_y: '' })).toBeNull();
    expect(normalizeMarket({ listing_id: '2', listing_name: 'Null island', location_x: '0', location_y: '0' })).toBeNull();
  });
});
