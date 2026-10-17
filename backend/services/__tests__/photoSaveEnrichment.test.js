// Build my map saves get the manual-save Google enrichment (Wes, 2026-10-17):
// Google's photo and details, never over the person's own photo.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../googleEnrichment', () => ({
  enrichSaveFromGoogle: jest.fn(async (draft) => {
    if (draft.name === 'Nowhere') return false;
    Object.assign(draft, {
      googlePlaceId: 'g_' + draft.name, rating: 4.6, phone: '(704) 555-0100',
      photos: draft.photos && draft.photos.length ? draft.photos : ['https://firebasestorage.googleapis.com/google.jpg']
    });
    return true;
  })
}));

const { enrichPhotoSaves } = require('../importService');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const places = () => mockDb.collection(COLLECTIONS.PLACES);

beforeEach(() => mockDb.rows(COLLECTIONS.PLACES).clear());

test('a bare photo save gets Google photo and details', async () => {
  await places().doc('a').set({ name: "Goldie's", location: { type: 'Point', coordinates: [-80.85, 35.21] }, photos: [] });
  const added = await enrichPhotoSaves(['a']);
  const saved = (await places().doc('a').get()).data();
  expect(saved).toMatchObject({ googlePlaceId: "g_Goldie's", rating: 4.6, phone: '(704) 555-0100', photoSource: 'google_places' });
  expect(saved.photos).toEqual(['https://firebasestorage.googleapis.com/google.jpg']);
  expect(added).toEqual(['https://firebasestorage.googleapis.com/google.jpg']);
});

test("the person's own photo is never replaced", async () => {
  await places().doc('b').set({ name: 'Cafe', photos: ['https://firebasestorage.googleapis.com/mine.jpg'] });
  const added = await enrichPhotoSaves(['b']);
  const saved = (await places().doc('b').get()).data();
  expect(saved.photos).toEqual(['https://firebasestorage.googleapis.com/mine.jpg']);
  expect(saved.googlePlaceId).toBe('g_Cafe');
  expect(added).toEqual([]);
});

test('no Google match or already linked: left as is', async () => {
  await places().doc('c').set({ name: 'Nowhere', photos: [] });
  await places().doc('d').set({ name: 'Linked', googlePlaceId: 'g_x', photos: [] });
  await enrichPhotoSaves(['c', 'd', 'missing']);
  expect((await places().doc('c').get()).data().googlePlaceId).toBeUndefined();
  expect((await places().doc('d').get()).data().googlePlaceId).toBe('g_x');
});
