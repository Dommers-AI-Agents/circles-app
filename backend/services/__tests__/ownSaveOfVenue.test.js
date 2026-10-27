jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../globalPlaceResolver', () => ({
  findCanonicalByNameAndLocation: jest.fn(),
  haversineMeters: (lat1, lng1, lat2, lng2) => {
    const R = 6371000, r = (d) => d * Math.PI / 180;
    const a = Math.sin(r(lat2 - lat1) / 2) ** 2 + Math.cos(r(lat1)) * Math.cos(r(lat2)) * Math.sin(r(lng2 - lng1) / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
  }
}));

const { pickByDistance, coordsOf } = require('../ownSaveOfVenue');
const doc = (id, location) => ({ id, data: () => ({ location }) });
const at = (lat, lng) => ({ coordinates: [lng, lat] });

describe('pickByDistance', () => {
  const here = coordsOf(at(40.1360, -74.0771));
  test('the same-named save at this spot', () => {
    expect(pickByDistance([doc('far', at(40.30, -74.10)), doc('near', at(40.1361, -74.0772))], here).id).toBe('near');
  });
  test('a same-named branch across town is not this place', () => {
    expect(pickByDistance([doc('far', at(40.30, -74.10))], here)).toBeNull();
  });
  test('an unlocated legacy save still counts when nothing nearer exists', () => {
    expect(pickByDistance([doc('legacy', null)], here).id).toBe('legacy');
  });
});

test('coordsOf reads GeoJSON and lat/lng', () => {
  expect(coordsOf({ coordinates: [-74, 40] })).toEqual({ lng: -74, lat: 40 });
  expect(coordsOf({ latitude: 40, longitude: -74 })).toEqual({ lng: -74, lat: 40 });
  expect(coordsOf(null)).toBeNull();
});

// findOwnSaveOfStore: a store record → the user's save, by whichever key the
// store carries. The fake Firestore answers equality queries over `docs`.
describe('findOwnSaveOfStore', () => {
  const makeDb = (docs) => {
    const query = (filters) => ({
      where: (field, op, value) => query([...filters, { field, op, value }]),
      limit: () => query(filters),
      get: async () => {
        const hits = docs.filter((d) => filters.every(({ field, op, value }) => {
          const actual = d.data()[field] === undefined ? null : d.data()[field];
          return op === 'in' ? value.includes(actual) : actual === value;
        }));
        return { empty: hits.length === 0, docs: hits };
      }
    });
    return { collection: () => query([]) };
  };
  const save = (id, fields) => ({ id, data: () => ({ addedBy: 'wes', deletedAt: null, ...fields }) });
  const resolver = require('../globalPlaceResolver');

  const load = (docs) => {
    jest.resetModules();
    jest.doMock('../../config/firebase', () => ({ getFirestore: () => makeDb(docs) }));
    jest.doMock('../globalPlaceResolver', () => ({
      ...resolver,
      resolveGlobalPlace: jest.fn(async () => ({ globalPlaceDoc: null })),
      findCanonicalByNameAndLocation: jest.fn(async () => null)
    }));
    return require('../ownSaveOfVenue').findOwnSaveOfStore;
  };

  test('a store enrolled by hand (no Google id) is found by its name near its spot', async () => {
    const find = load([save('p1', { name: 'Test Bakery', location: { coordinates: [-80.8431, 35.2271] } })]);
    const venue = { venueId: 'v1', venueName: 'Test Bakery', location: { lat: 35.2272, lng: -80.8432 } };
    expect((await find({ userId: 'wes', venue })).id).toBe('p1');
  });

  test("the store's display name differing from its place name still matches", async () => {
    const find = load([save('p2', { name: "Sal's Pizzeria", location: { coordinates: [-80.8431, 35.2271] } })]);
    const venue = { venueId: 'v2', venueName: "Sal's", placeName: "Sal's Pizzeria", location: { lat: 35.2271, lng: -80.8431 } };
    expect((await find({ userId: 'wes', venue })).id).toBe('p2');
  });

  test('the canonical venue id finds a save that carries no Google id (the scanned bakery)', async () => {
    const find = load([save('p0', { globalPlaceId: 'gp1', name: 'Something Else' })]);
    const venue = { venueId: 'v0', venueName: 'Test Bakery', globalPlaceId: 'gp1', location: { lat: 35.2271, lng: -80.8431 } };
    expect((await find({ userId: 'wes', venue })).id).toBe('p0');
  });

  test('an online-only brand never matches by name', async () => {
    const find = load([save('p5', { name: 'Knight ATV', location: { coordinates: [-80.8431, 35.2271] } })]);
    const venue = { venueId: 'v5', venueName: 'Knight ATV', isVirtual: true, location: { lat: 35.2271, lng: -80.8431 } };
    expect(await find({ userId: 'wes', venue })).toBeNull();
  });

  test('a Google id match wins without a name', async () => {
    const find = load([save('p3', { googlePlaceId: 'g1', name: 'Other Name' })]);
    expect((await find({ userId: 'wes', venue: { venueId: 'v3', venueName: 'Bakery', googlePlaceId: 'g1' } })).id).toBe('p3');
  });

  test('not saved: null, and a same-named branch across town does not count', async () => {
    const find = load([save('p4', { name: 'Test Bakery', location: { coordinates: [-80.5, 35.6] } })]);
    const venue = { venueId: 'v4', venueName: 'Test Bakery', location: { lat: 35.2271, lng: -80.8431 } };
    expect(await find({ userId: 'wes', venue })).toBeNull();
  });
});
