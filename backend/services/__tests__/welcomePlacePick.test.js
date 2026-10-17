const { pickWelcomePlace, isStreetAddressName } = require('../welcomePlacePick');

test('street addresses are recognised, venue names are not', () => {
  for (const n of ['600 Fifth Ave', '121 W Trade St', '1600 Broadway', '35-12 31st Ave N', '300 East Blvd.']) {
    expect(isStreetAddressName(n)).toBe(true);
  }
  for (const n of ['21 Club', '1 Hotel Brooklyn Bridge', 'Carmine\'s', 'Fifth Avenue Bistro', '7th Street Public Market']) {
    expect(isStreetAddressName(n)).toBe(false);
  }
  expect(isStreetAddressName('412 Elmhurst', '412 Elmhurst, Charlotte, NC')).toBe(true);
});

test('only public-circle, open, non-want-to-go venues; best rated wins', () => {
  const pub = new Set(['pub']);
  const places = [
    { id: 'addr', name: '600 Fifth Ave', circleId: 'pub', userRating: 10, photos: ['x'] },
    { id: 'want', name: 'Le Bernardin', circleId: 'pub', tags: ['google-import', 'want-to-go'], userRating: 10 },
    { id: 'hidden', name: 'Secret Bar', circleId: 'net', userRating: 10 },
    { id: 'priv', name: 'Home Spot', circleId: 'pub', privacy: 'private', userRating: 10 },
    { id: 'gone', name: 'Closed Cafe', circleId: 'pub', deletedAt: '2026-01-01', userRating: 10 },
    { id: 'ok', name: 'Carmine\'s', circleId: 'pub', userRating: 6, category: 'restaurant' },
    { id: 'best', name: 'Pizza Spot', circleId: 'pub', userRating: 9, photos: ['p'] }
  ];
  expect(pickWelcomePlace(places, pub).id).toBe('best');
  expect(pickWelcomePlace(places.filter(p => p.id !== 'best' && p.id !== 'ok'), pub)).toBeNull();
});

test('ties at the top are picked at random, never a lower score', () => {
  const pub = new Set(['pub']);
  const places = [
    { id: 'a', name: 'A Cafe', circleId: 'pub', userRating: 10 },
    { id: 'b', name: 'B Bar', circleId: 'pub', userRating: 10 },
    { id: 'c', name: 'C Deli', circleId: 'pub', userRating: 3 }
  ];
  expect(pickWelcomePlace(places, pub, { random: () => 0 }).id).toBe('a');
  expect(pickWelcomePlace(places, pub, { random: () => 0.99 }).id).toBe('b');
});

test('a place to discover beats a service at the same rating', () => {
  const pub = new Set(['pub']);
  const places = [
    { id: 'tires', name: 'Tire Shop', circleId: 'pub', userRating: 10, category: 'service' },
    { id: 'bar', name: 'The Blind Pig', circleId: 'pub', userRating: 10, category: 'bar' }
  ];
  expect(pickWelcomePlace(places, pub, { random: () => 0 }).id).toBe('bar');
});

test('near the new user when Wes has a favorite there, otherwise anywhere', () => {
  const pub = new Set(['pub']);
  const charlotte = { latitude: 35.2169, longitude: -80.8593 };
  const places = [
    { id: 'shore', name: 'La Dolce Vita', circleId: 'pub', userRating: 10, photos: ['p'],
      location: { type: 'Point', coordinates: [-74.0218, 40.1784] } },
    { id: 'clt', name: 'Optimist Hall', circleId: 'pub', userRating: 8,
      location: { type: 'Point', coordinates: [-80.8253, 35.2340] } }
  ];
  expect(pickWelcomePlace(places, pub, { near: charlotte }).id).toBe('clt');
  expect(pickWelcomePlace(places, pub, { near: { latitude: 47.6, longitude: -122.3 } }).id).toBe('shore');
  expect(pickWelcomePlace(places, pub).id).toBe('shore');
});
