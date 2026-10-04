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
