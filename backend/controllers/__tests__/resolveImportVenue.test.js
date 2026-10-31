// PUT /places/:id/resolve on an import already linked to a canonical venue:
// the venue's location/address are the one source. A venue without a map
// point takes the resolved one through the one write path (every save and
// the store follow); a located venue is never moved by one saver's import.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../config/config', () => ({ googleMapsApiKey: 'test-key' }));
jest.mock('../../services/globalPlaceResolver', () => ({
  ensureGlobalPlaceLink: async (doc) => doc.data().globalPlaceId || null,
  findCanonicalByNameAndLocation: async () => null
}));
jest.mock('../../services/circleLocationSummary', () => ({ indexSavedPlace: () => {} }));
jest.mock('../../services/circleCover', () => ({ ensureCircleCoverImage: async () => {} }));
jest.mock('../../services/requestDeduplicator', () => ({}));

const { resolveImportedPlace } = require('../places/placeVenueMaintenanceController');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const row = (col, id) => mockDb.rows(col).get(id);
const call = async (user, id, body) => {
  const res = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
  await resolveImportedPlace({ user, params: { id }, body }, res);
  return res;
};
const BODY = { latitude: 35.21, longitude: -80.86, address: '1540 S Church St, Charlotte, NC 28203, USA' };

beforeEach(async () => {
  for (const name of ['globalPlaces', 'places', 'stickerVenues', 'users', 'circles']) mockDb.rows(name).clear();
  await put('places', 'p1', { globalPlaceId: 'g1', name: 'Bakery', addedBy: 'u1', address: 'Address pending', needsResolution: true });
  await put('places', 'p2', { globalPlaceId: 'g1', name: 'Bakery', addedBy: 'u2', address: 'Address pending' });
});

test('an unclaimed venue with no map point takes the resolved one: venue, every save, and the city', async () => {
  await put('globalPlaces', 'g1', { name: 'Bakery', address: 'Address pending', category: 'cafe' });
  const res = await call({ uid: 'u1' }, 'p1', BODY);
  expect(res.statusCode).toBe(200);
  const g = row('globalPlaces', 'g1');
  expect(g.location).toEqual({ type: 'Point', coordinates: [-80.86, 35.21] });
  expect(g.address).toBe(BODY.address);
  expect(g.stateCode).toBe('NC');
  expect(row('places', 'p2')).toMatchObject({ location: g.location, address: BODY.address });
});

test('a claimed store with no map point: its venue is left to its team; the save still resolves', async () => {
  await put('globalPlaces', 'g1', { name: 'Bakery', address: 'Address pending', category: 'cafe' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Bakery', ownerUserId: 'owner' });
  await call({ uid: 'u1' }, 'p1', BODY);
  expect(row('globalPlaces', 'g1').location).toBeUndefined();
  expect(row('places', 'p1').location).toEqual({ type: 'Point', coordinates: [-80.86, 35.21] });
  expect(row('places', 'p2').location).toBeUndefined();
});

test("the store's owner resolving their own import does set the store's map point (store follows)", async () => {
  await put('globalPlaces', 'g1', { name: 'Bakery', address: 'Address pending', category: 'cafe' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Bakery', ownerUserId: 'u1' });
  await call({ uid: 'u1' }, 'p1', BODY);
  expect(row('globalPlaces', 'g1').location).toEqual({ type: 'Point', coordinates: [-80.86, 35.21] });
  expect(row('stickerVenues', 'v1')).toMatchObject({ location: { lat: 35.21, lng: -80.86 }, placeAddress: BODY.address });
});

test('a venue that already has a map point keeps it, and the save takes the venue\'s', async () => {
  await put('globalPlaces', 'g1', { name: 'Bakery', address: '1 Main St, Charlotte, NC', category: 'cafe',
    location: { type: 'Point', coordinates: [-80.84, 35.22] }, geohash: 'dnq8' });
  await call({ uid: 'u1' }, 'p1', BODY);
  expect(row('globalPlaces', 'g1').location.coordinates).toEqual([-80.84, 35.22]);
  expect(row('places', 'p1')).toMatchObject({ location: { type: 'Point', coordinates: [-80.84, 35.22] }, geohash: 'dnq8', address: '1 Main St, Charlotte, NC' });
});

test('someone else\'s save: refused, as before', async () => {
  await put('globalPlaces', 'g1', { name: 'Bakery', address: 'Address pending' });
  const res = await call({ uid: 'u2' }, 'p1', BODY);
  expect(res.statusCode).toBe(403);
  expect(row('globalPlaces', 'g1').location).toBeUndefined();
});
