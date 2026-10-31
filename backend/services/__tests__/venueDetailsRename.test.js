// Renaming a place renames its store everywhere (Wes, 2026-10-31: Test Bakery
// → Sal's Bakery changed the place page but not the Store screens, which read
// the store's own venueName). The store's slug stays, so QR codes keep working.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
mockDb.batch = () => {
  const ops = [];
  return { update(ref, data) { ops.push(() => ref.update(data)); return this; }, async commit() { for (const op of ops) await op(); } };
};

const { updateVenueDetails } = require('../venueDetailsService');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(async () => {
  for (const name of ['globalPlaces', 'places', 'stickerVenues', 'users']) mockDb.rows(name).clear();
  await put('globalPlaces', 'g1', { name: 'Test Bakery (Demo)', category: 'cafe', location: { type: 'Point', coordinates: [-80.86, 35.21] } });
  await put('places', 'p1', { globalPlaceId: 'g1', name: 'Test Bakery (Demo)', addedBy: 'owner' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Test Bakery (Demo)', placeName: 'Test Bakery (Demo)',
    ownerUserId: 'owner', slug: 'test-bakery-demo' });
});

test('the owner renames the place: venue record, saves and the store all carry the new name; the slug stays', async () => {
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'owner' }, fields: { name: "Sal's Bakery (Demo)" } });
  expect(mockDb.rows('globalPlaces').get('g1').name).toBe("Sal's Bakery (Demo)");
  expect(mockDb.rows('places').get('p1').name).toBe("Sal's Bakery (Demo)");
  const store = mockDb.rows('stickerVenues').get('v1');
  expect(store).toMatchObject({ venueName: "Sal's Bakery (Demo)", placeName: "Sal's Bakery (Demo)", slug: 'test-bakery-demo' });
});

test('a change that is not the name leaves the store name alone', async () => {
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'owner' }, fields: { description: 'Fresh bread daily' } });
  expect(mockDb.rows('stickerVenues').get('v1').venueName).toBe('Test Bakery (Demo)');
});

test("a customer's points list shows the store's current name, not the one saved when they earned", async () => {
  const rewardService = require('../rewardService');
  await put('users', 'cust', { rewardPoints: 50, rewardPointsByVenue: { v1: { points: 50, venueName: 'Test Bakery (Demo)' } } });
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'owner' }, fields: { name: "Sal's Bakery (Demo)" } });
  const userData = mockDb.rows('users').get('cust');
  expect(await rewardService.venueBalancesWithNames(userData)).toEqual([{ venueId: 'v1', venueName: "Sal's Bakery (Demo)", points: 50 }]);
  // A store that no longer exists keeps the saved name
  const gone = { rewardPointsByVenue: { vX: { points: 5, venueName: 'Old Shop' } } };
  expect(await rewardService.venueBalancesWithNames(gone)).toEqual([{ venueId: 'vX', venueName: 'Old Shop', points: 5 }]);
});
