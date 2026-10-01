// security audit 2026-10-01: the Google Places response cache is bounded.
const { PlaceCache } = require('../placeCache');

beforeEach(() => jest.spyOn(console, 'log').mockImplementation(() => {}));
afterEach(() => jest.restoreAllMocks());

test('evicts the least-recently-used entry past maxEntries', () => {
  const cache = new PlaceCache();
  cache.maxEntries = 3;
  cache.set('placeDetails', 'a', 1);
  cache.set('placeDetails', 'b', 2);
  cache.set('placeDetails', 'c', 3);
  expect(cache.get('placeDetails', 'a')).toBe(1); // a is now most recent
  cache.set('placeDetails', 'd', 4); // evicts b
  expect(cache.cache.size).toBe(3);
  expect(cache.get('placeDetails', 'b')).toBeNull();
  expect(cache.get('placeDetails', 'a')).toBe(1);
  expect(cache.get('placeDetails', 'd')).toBe(4);
});

test('re-setting an existing key does not evict others', () => {
  const cache = new PlaceCache();
  cache.maxEntries = 2;
  cache.set('placeDetails', 'a', 1);
  cache.set('placeDetails', 'b', 2);
  cache.set('placeDetails', 'a', 3);
  expect(cache.get('placeDetails', 'b')).toBe(2);
  expect(cache.get('placeDetails', 'a')).toBe(3);
});

test('defaults to 5000 entries', () => {
  expect(new PlaceCache().maxEntries).toBe(5000);
});
