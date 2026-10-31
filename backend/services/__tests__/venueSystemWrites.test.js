// System writers (Google enrichment, Google/LLM category changes, venue
// propagation) reach the store record too, through the one venue-details
// path or the one category fan-out (Wes, 2026-10-31: "make sure data points
// like store name are stored in the db and pulled from one place").
// FakeFirestore stores dotted update keys literally ('googleData.phone').
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../config/config', () => ({ googleMapsApiKey: 'test-key' }));
jest.mock('@googlemaps/google-maps-services-js', () => ({
  Client: class {
    async findPlaceFromText() {
      return { data: { candidates: [{ place_id: 'ChIJsal', name: "Sal's Bakery" }] } };
    }
    async placeDetails() {
      return { data: { result: {
        name: "Sal's Bakery", formatted_address: '1540 S Church St, Charlotte, NC 28203, USA',
        formatted_phone_number: '(704) 555-0100', website: 'https://sals.example',
        opening_hours: { weekday_text: ['Monday: 7 AM – 3 PM'] }, types: ['bakery', 'cafe']
      } } };
    }
  }
}));
const mockCanonical = { doc: null };
jest.mock('../globalPlaceResolver', () => ({ findCanonicalByNameAndLocation: async () => mockCanonical.doc }));
jest.mock('../storage', () => ({ downloadAndUploadMultipleImages: async () => ({ uploadedUrls: [] }) }));
jest.mock('../categoryClassifier', () => ({ isEnabled: () => false, MODEL: 'none' }));

const { enrichSaveFromGoogle } = require('../googleEnrichment');
const { syncCategoryToSaves } = require('../venueGoogleSignals');
const { runCategorySweep } = require('../categorySweep');
const { propagateVenueUpdates } = require('../placeVenueSync');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const row = (col, id) => mockDb.rows(col).get(id);
const OWNER_HOURS = [{ day: 1, open: '08:00', close: '14:00', isClosed: false }];

beforeEach(async () => {
  for (const name of ['globalPlaces', 'places', 'stickerVenues']) mockDb.rows(name).clear();
  await put('globalPlaces', 'g1', { name: 'Test Bakery', address: '1540 S Church St', category: 'cafe', categorySource: 'client',
    location: { type: 'Point', coordinates: [-80.86, 35.21] },
    googleData: { hoursSource: 'owner', openingHours: OWNER_HOURS } });
  await put('places', 'p1', { globalPlaceId: 'g1', name: 'Test Bakery', addedBy: 'u1', category: 'cafe' });
  await put('places', 'p2', { globalPlaceId: 'g1', name: 'Test Bakery', addedBy: 'u2', category: 'cafe' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Test Bakery', placeName: 'Test Bakery',
    placeAddress: '1540 S Church St', category: 'cafe', ownerUserId: 'owner', slug: 'test-bakery' });
  mockCanonical.doc = await mockDb.collection('globalPlaces').doc('g1').get();
});

test('Google enrichment of a bare venue renames the venue, every save and the store; owner hours stay', async () => {
  const save = { name: 'Test Bakery', location: { type: 'Point', coordinates: [-80.86, 35.21] } };
  expect(await enrichSaveFromGoogle(save)).toBe(true);

  const g = row('globalPlaces', 'g1');
  expect(g).toMatchObject({ name: "Sal's Bakery", nameLower: "sal's bakery", googlePlaceId: 'ChIJsal',
    address: '1540 S Church St, Charlotte, NC 28203, USA', 'googleData.phone': '(704) 555-0100', 'googleData.website': 'https://sals.example' });
  // The owner's hours: neither replaced by Google's nor re-stamped
  expect(g['googleData.openingHours']).toBeUndefined();
  expect(g['googleData.hoursSource']).toBeUndefined();
  expect(g.googleData).toEqual({ hoursSource: 'owner', openingHours: OWNER_HOURS });
  expect(row('places', 'p2')).toMatchObject({ name: "Sal's Bakery", address: g.address });
  expect(row('stickerVenues', 'v1')).toMatchObject({ venueName: "Sal's Bakery", placeName: "Sal's Bakery", placeAddress: g.address, slug: 'test-bakery' });
});

test('Google hours still fill a venue whose hours did not come from its owner', async () => {
  await mockDb.collection('globalPlaces').doc('g1').update({ googleData: {} });
  mockCanonical.doc = await mockDb.collection('globalPlaces').doc('g1').get();
  await enrichSaveFromGoogle({ name: 'Test Bakery', location: { type: 'Point', coordinates: [-80.86, 35.21] } });
  expect(row('globalPlaces', 'g1')['googleData.openingHours']).toEqual([{ day: 1, hours: 'Monday: 7 AM – 3 PM' }]);
});

test('a Google category change reaches every save and the store', async () => {
  await syncCategoryToSaves('g1', 'restaurant', 'now');
  expect(row('places', 'p1').category).toBe('restaurant');
  expect(row('places', 'p2').category).toBe('restaurant');
  expect(row('stickerVenues', 'v1').category).toBe('restaurant');
});

test('a store found only by Google id follows the category too', async () => {
  await put('stickerVenues', 'v1', { googlePlaceId: 'ChIJsal', venueName: 'Test Bakery', category: 'cafe' });
  await syncCategoryToSaves('g1', 'restaurant', 'now', { venue: { googlePlaceId: 'ChIJsal' } });
  expect(row('stickerVenues', 'v1').category).toBe('restaurant');
});

test('the nightly sweep moves a venue out of Other on the venue, its saves and its store, keeping its bookkeeping', async () => {
  await put('globalPlaces', 'g2', { name: "Joe's Pizza Restaurant", category: 'other' });
  await put('places', 'p3', { globalPlaceId: 'g2', name: "Joe's Pizza Restaurant", category: 'other' });
  await put('stickerVenues', 'v2', { globalPlaceId: 'g2', venueName: "Joe's Pizza Restaurant", category: 'other' });
  const report = await runCategorySweep();
  expect(report.freeTierResolved).toBe(1);
  const g = row('globalPlaces', 'g2');
  expect(g.category).toBe('restaurant');
  expect(g).toMatchObject({ categoryBefore: 'other', categorySource: expect.any(String) });
  expect(g.categorySource).not.toBe('manual');
  expect(row('places', 'p3').category).toBe('restaurant');
  expect(row('stickerVenues', 'v2').category).toBe('restaurant');
});

test('venue propagation: shared details go through the one path (store too); ratings stay on the canonical record', async () => {
  await propagateVenueUpdates('p1', 'g1', { name: 'New Name', rating: 4.7, delivery: true, photos: ['x'] });
  const g = row('globalPlaces', 'g1');
  expect(g).toMatchObject({ name: 'New Name', 'googleData.rating': 4.7, 'googleData.delivery': true });
  expect(g.photos).toBeUndefined();
  expect(row('places', 'p1').name).toBe('New Name');
  expect(row('places', 'p2').name).toBe('New Name');
  expect(row('stickerVenues', 'v1').venueName).toBe('New Name');
});

test('venue propagation with ratings only leaves the details alone', async () => {
  await propagateVenueUpdates('p1', 'g1', { rating: 4.2, userRatingsTotal: 10, updatedAt: 'x' });
  expect(row('globalPlaces', 'g1')).toMatchObject({ name: 'Test Bakery', 'googleData.rating': 4.2, 'googleData.userRatingsTotal': 10 });
  expect(row('stickerVenues', 'v1').venueName).toBe('Test Bakery');
});
