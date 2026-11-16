// Wes, 2026-11-16: Brittany's mom's and dad's houses kept showing on the
// feed. An activity about a hidden place reaches only the person who did it.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, admin: {} }));
const { isAboutHiddenVenue } = require('../activity/hiddenPlaceGate');

const db = mockDb;
beforeAll(() => {
  db.collection('globalPlaces').doc('home').set({ name: "Brittany's Mom and Steve", approvalStatus: 'rejected' });
  db.collection('globalPlaces').doc('cafe').set({ name: 'Over Easy', approvalStatus: 'approved' });
  db.collection('places').doc('homeSave').set({ globalPlaceId: 'home' });
  db.collection('places').doc('cafeSave').set({ globalPlaceId: 'cafe' });
});

test('a check-in, save or photo at a hidden place is owner-only', async () => {
  expect(await isAboutHiddenVenue('check_in', 'ck1', { globalPlaceId: 'home' }, { db })).toBe(true);
  expect(await isAboutHiddenVenue('place', 'homeSave', {}, { db })).toBe(true);
  expect(await isAboutHiddenVenue('place', 'home', {}, { db })).toBe(true);
  expect(await isAboutHiddenVenue('place_video', 'v1', { placeId: 'homeSave' }, { db })).toBe(true);
});

test('a public place, or a row about no place, goes to the feed as before', async () => {
  expect(await isAboutHiddenVenue('place', 'cafeSave', {}, { db })).toBe(false);
  expect(await isAboutHiddenVenue('check_in', 'ck2', { globalPlaceId: 'cafe' }, { db })).toBe(false);
  expect(await isAboutHiddenVenue('user', 'u1', {}, { db })).toBe(false);
  expect(await isAboutHiddenVenue('place', 'missing', {}, { db })).toBe(false);
});
