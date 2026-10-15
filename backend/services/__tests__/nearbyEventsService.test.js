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

const service = require('../nearbyEventsService');

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

const payload = (events) => ({ _embedded: { events } });

beforeEach(() => {
  mockStore.clear();
  service._memory.clear();
  global.fetch = jest.fn();
});

test('normalizes an event: image, category, price, distance', () => {
  const [event] = service.normalizeEvents(payload([tmEvent()]), CLT);
  expect(event).toMatchObject({
    id: 'e1', name: 'Jazz Night', startLocalDate: '2026-10-18', startLocalTime: '20:00:00',
    venueName: 'The Fillmore', city: 'Charlotte', category: 'Jazz', imageUrl: 'right.jpg',
    priceMin: 25, priceMax: 60, currency: 'USD', url: 'https://www.ticketmaster.com/event/e1'
  });
  expect(event.distanceMeters).toBeGreaterThan(500);
  expect(event.distanceMeters).toBeLessThan(1000);
});

test('drops cancelled events and keeps one date per show', () => {
  const events = service.normalizeEvents(payload([
    tmEvent({ id: 'late', dates: { start: { localDate: '2026-10-20', localTime: '20:00:00' } } }),
    tmEvent({ id: 'early', dates: { start: { localDate: '2026-10-17', localTime: '19:00:00' } } }),
    tmEvent({ id: 'gone', name: 'Cancelled Show', dates: { start: { localDate: '2026-10-17' }, status: { code: 'cancelled' } } }),
    tmEvent({ id: 'other', name: 'Comedy Hour', dates: { start: { localDate: '2026-10-16' } } })
  ]), CLT);
  expect(events.map((e) => e.id)).toEqual(['other', 'late']);
});

test('no key, no coordinates → no events and no request', async () => {
  expect(await service.getNearbyEvents(CLT.lat, CLT.lng, { apiKey: '' })).toEqual([]);
  expect(await service.getNearbyEvents(NaN, CLT.lng, { apiKey: 'k' })).toEqual([]);
  expect(global.fetch).not.toHaveBeenCalled();
});

test('fetches once, then serves the cell from cache with the caller\'s distance', async () => {
  global.fetch.mockResolvedValue({ ok: true, json: async () => payload([tmEvent()]) });
  const now = new Date('2026-10-15T12:00:00Z');
  const first = await service.getNearbyEvents(CLT.lat, CLT.lng, { apiKey: 'k', now });
  expect(first).toHaveLength(1);
  expect(global.fetch).toHaveBeenCalledTimes(1);
  expect(global.fetch.mock.calls[0][0]).toContain('latlong=35.2271%2C-80.8431');

  const second = await service.getNearbyEvents(CLT.lat + 0.001, CLT.lng, { apiKey: 'k', now });
  expect(global.fetch).toHaveBeenCalledTimes(1);
  expect(second[0].distanceMeters).not.toBe(first[0].distanceMeters);

  // Another instance (empty memory) reads Firestore instead of Ticketmaster
  service._memory.clear();
  await service.getNearbyEvents(CLT.lat, CLT.lng, { apiKey: 'k', now });
  expect(global.fetch).toHaveBeenCalledTimes(1);
});

test('upstream failure or timeout → empty, not an error', async () => {
  global.fetch.mockResolvedValueOnce({ ok: false, status: 401, json: async () => ({}) });
  expect(await service.getNearbyEvents(CLT.lat, CLT.lng, { apiKey: 'bad' })).toEqual([]);
  global.fetch.mockRejectedValueOnce(Object.assign(new Error('aborted'), { name: 'AbortError' }));
  expect(await service.getNearbyEvents(CLT.lat, CLT.lng, { apiKey: 'k' })).toEqual([]);
});
