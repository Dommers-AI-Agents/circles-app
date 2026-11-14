// One venue record per place (Wes, 2026-11-04). The matcher must find the
// existing venue for a differently-worded name at the same spot, a known
// venue id follows merges and refuses deleted records, and a Google id has
// one live holder.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const geofire = require('geofire-common');
const { buildSearchTokens } = require('../../models/GlobalPlace');
const resolver = require('../globalPlaceResolver');

const venue = (id, data) => {
  const [lng, lat] = data.location.coordinates;
  mockDb.collection('globalPlaces').doc(id).set({
    searchTokens: buildSearchTokens(data.name), geohash: geofire.geohashForLocation([lat, lng]), ...data
  });
};
const FRESH_MONKEE = { type: 'Point', coordinates: [-80.8561543, 35.2177104] };

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
});

test("Apple's longer name at the same spot finds the existing venue", async () => {
  process.env.VENUE_SIMILAR_NAME_MATCH = '1';
  venue('real', { name: 'Fresh Monkee', googlePlaceId: 'ChIJfm', location: FRESH_MONKEE });
  // "southend", the longest word, is not in the real venue's tokens
  const found = await resolver.findCanonicalByNameAndLocation('Fresh Monkee - Southend',
    { coordinates: [-80.8561686, 35.2177166] });
  expect(found && found.id).toBe('real');
});

test('of two equal names nearby, the record with a Google id wins', async () => {
  venue('bare', { name: 'Not Just Coffee', location: { type: 'Point', coordinates: [-80.8600, 35.2100] } });
  venue('google', { name: 'Not Just Coffee', googlePlaceId: 'ChIJnjc', location: { type: 'Point', coordinates: [-80.8601, 35.2101] } });
  const found = await resolver.findCanonicalByNameAndLocation('Not Just Coffee', { coordinates: [-80.8600, 35.2100] });
  expect(found.id).toBe('google');
});

test('a known venue id follows a merge and refuses a deleted record', async () => {
  venue('survivor', { name: 'Goldies', location: FRESH_MONKEE });
  venue('retired', { name: 'Goldies', location: FRESH_MONKEE, mergedInto: 'survivor', deletedAt: 'x' });
  venue('gone', { name: 'Gone', location: FRESH_MONKEE, deletedAt: 'x' });
  expect((await resolver.liveVenueDoc('retired')).id).toBe('survivor');
  expect(await resolver.liveVenueDoc('gone')).toBeNull();
  expect(await resolver.liveVenueDoc('nope')).toBeNull();
  expect(await resolver.liveVenueDoc(null)).toBeNull();
});

test('a Google id has one live holder; merged and deleted records never hold it', async () => {
  venue('old', { name: 'Goldies', googlePlaceId: 'ChIJg', location: FRESH_MONKEE, mergedInto: 'live' });
  venue('live', { name: 'Goldies', googlePlaceId: 'ChIJg', location: FRESH_MONKEE });
  expect((await resolver.findVenueByGooglePlaceId('ChIJg')).id).toBe('live');
  expect(await resolver.findVenueByGooglePlaceId(null)).toBeNull();
});

test("a save's parallel first reads make one venue, not one each", async () => {
  // 2026-11-11: opening a Google Imports save fired the place page's requests
  // together and made three "Roosevelt Overlook Campground" venues in 23 ms
  mockDb.collection('places').doc('save1').set({ name: 'Roosevelt Overlook Campground', address: 'Address pending', addedBy: 'u1', category: 'other' });
  const save = await mockDb.collection('places').doc('save1').get();
  const results = await Promise.all([1, 2, 3].map(() => resolver.createGlobalPlaceFromLegacy(save)));
  expect(new Set(results.map((r) => r.resolvedId)).size).toBe(1);
  expect(results.filter((r) => !r.joined)).toHaveLength(1);
  expect(mockDb.collection('globalPlaces').store.docs.size).toBe(1);
});
