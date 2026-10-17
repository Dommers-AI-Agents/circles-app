// Build my map never saves a place twice (Wes, 2026-10-17): Apple's place id
// matches the venue exactly, and Apple/Google name variants nearby match too.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../googleEnrichment', () => ({ enrichSaveFromGoogle: jest.fn(async () => false) }));
jest.mock('../globalPlaceResolver', () => ({ ensureGlobalPlaceLink: jest.fn(async () => null) }));
jest.mock('../subscriptionLimitService', () => ({
  canImport: jest.fn(async () => ({ canImport: true })),
  photoPlacesAllowance: jest.fn(async () => ({ remaining: Infinity, max: Infinity })),
  checkPlaceLimit: jest.fn(async () => ({ canAdd: true }))
}), { virtual: false });

const importService = require('../importService');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const ME = 'me';

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
  mockDb.collection(COLLECTIONS.USERS).doc(ME).set({ displayName: 'Me' });
});

const photosImport = (places) => importService.executeImport(ME, {
  source: 'photos', target: { kind: 'photos' }, lists: [{ name: 'Places from my photos', places }]
});

test("the same venue saved under Google's name is matched by Apple's place id", async () => {
  // Saved by hand as "Goldie's on Morehead"; the venue knows its Apple id
  mockDb.collection('globalPlaces').doc('venue1').set({ name: "Goldie's on Morehead", applePlaceId: 'I123' });
  mockDb.collection(COLLECTIONS.PLACES).doc('mine').set({ addedBy: ME, name: "Goldie's on Morehead", circleId: 'c1',
    globalPlaceId: 'venue1', location: { type: 'Point', coordinates: [-80.86, 35.21] }, deletedAt: null });
  const result = await photosImport([{ name: 'Totally Different Name', applePlaceId: 'I123', lat: 35.3, lng: -80.9, address: 'x', category: 'restaurant' }]);
  expect(result.results[0]).toMatchObject({ created: 0, skippedDuplicates: 1 });
});

test('Apple and Google names for one place nearby are one place', () => {
  const index = { byNormName: new Map([["goldies on morehead", [{ placeId: 'mine', lat: 35.21, lng: -80.86 }]]]) };
  expect(importService.findNearbySimilarName(index, "Goldie's", 35.2103, -80.8602)).toMatchObject({ placeId: 'mine' });
  // Far away: a different branch, not a duplicate
  expect(importService.findNearbySimilarName(index, "Goldie's", 35.25, -80.86)).toBeNull();
  // Unrelated name nearby
  expect(importService.findNearbySimilarName(index, 'Indaco', 35.2103, -80.8602)).toBeNull();
});

test('two photo rows for one Apple place in the same save become one place, stamped with the id', async () => {
  const result = await photosImport([
    { name: 'Indaco', applePlaceId: 'I999', lat: 35.2154, lng: -80.8599, address: '2000 South Blvd', category: 'restaurant' },
    { name: 'Indaco Restaurant', applePlaceId: 'I999', lat: 35.2155, lng: -80.8598, address: '2000 S Blvd', category: 'restaurant' }
  ]);
  expect(result.results[0]).toMatchObject({ created: 1, skippedDuplicates: 1 });
  const saves = [...mockDb.rows(COLLECTIONS.PLACES).values()];
  expect(saves.map((p) => p.applePlaceId)).toEqual(['I999']);
});
