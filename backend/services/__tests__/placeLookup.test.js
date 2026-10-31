// Moments, suggestions and share links show a place's CURRENT name: the
// venue record is the one source, stored copies are only fallbacks
// (Wes, 2026-10-31).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../utils/networkAccess', () => ({
  getConnectionPairSnapshots: async () => [{ empty: true }, { empty: true }],
  getAcceptedConnectionSnapshots: async () => [{ docs: [] }, { docs: [] }]
}));
jest.mock('../notificationService', () => ({}));

const { fetchVenuesForSaves, withCurrentMomentPlaces } = require('../placeLookup');
const { updateVenueDetails } = require('../venueDetailsService');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const respond = () => ({ statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } });

beforeEach(async () => {
  for (const name of ['globalPlaces', 'places', 'stickerVenues', 'users', 'placeVideos', 'suggestions']) mockDb.rows(name).clear();
  await put('globalPlaces', 'g1', { name: 'Test Bakery', address: '1 Main St', photos: [{ url: 'https://x/cover.jpg' }],
    location: { type: 'Point', coordinates: [-80.86, 35.21] } });
  await put('globalPlaces', 'gone', { name: 'Closed', deletedAt: '2026-10-01' });
  await put('places', 'p1', { globalPlaceId: 'g1', name: 'Test Bakery', addedBy: 'u1' });
  await put('places', 'p-unlinked', { name: 'Somewhere', addedBy: 'u1' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Test Bakery', ownerUserId: 'owner' });
  await put('users', 'u1', { displayName: 'Sal' });
  // The owner renames the place after the moment and suggestion were made
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'owner' }, fields: { name: "Sal's Bakery", address: '2 Main St, Charlotte, NC' } });
});

test('saves map to their venue; unlinked saves and deleted venues are absent; a venue id works too', async () => {
  const m = await fetchVenuesForSaves(['p1', 'p1', 'p-unlinked', 'nope', 'g1', 'gone', null]);
  expect(m.get('p1')).toEqual({ globalPlaceId: 'g1', name: "Sal's Bakery", address: '2 Main St, Charlotte, NC', photo: 'https://x/cover.jpg' });
  expect(m.get('g1').name).toBe("Sal's Bakery");
  expect(m.has('p-unlinked')).toBe(false);
  expect(m.has('nope')).toBe(false);
  expect(m.has('gone')).toBe(false);
});

test('moments show the current place name and address; others keep what they stored', async () => {
  const out = await withCurrentMomentPlaces([
    { id: 'm1', placeId: 'p1', placeName: 'Test Bakery', placeAddress: '1 Main St' },
    { id: 'm2', placeId: 'p-unlinked', placeName: 'Somewhere' },
    { id: 'm3' }
  ]);
  expect(out[0]).toMatchObject({ id: 'm1', placeName: "Sal's Bakery", placeAddress: '2 Main St, Charlotte, NC' });
  expect(out[1]).toEqual({ id: 'm2', placeId: 'p-unlinked', placeName: 'Somewhere' });
  expect(out[2]).toEqual({ id: 'm3' });
});

test('a moment share link uses the current name', async () => {
  await put('placeVideos', 'm1', { placeId: 'p1', placeName: 'Test Bakery', userId: 'u1', visibility: 'public',
    uploadStatus: 'ready', deletedAt: null, thumbnailUrl: 'https://x/t.jpg' });
  const { getVideoShareInfo, generateVideoShareLink } = require('../../controllers/video/videoShareController');
  const info = respond();
  await getVideoShareInfo({ params: { videoId: 'm1' } }, info);
  expect(info.body.data.placeName).toBe("Sal's Bakery");
  const link = respond();
  await generateVideoShareLink({ params: { videoId: 'm1' }, user: { uid: 'u1' } }, link);
  expect(link.body.data).toMatchObject({ placeName: "Sal's Bakery", shareText: expect.stringContaining("Sal's Bakery") });
});

test("a suggestion's place card shows the current name and address; the sender's photos and the message spans stay", async () => {
  await put('suggestions', 's1', { userId: 'u1', createdAt: '2026-10-30', message: 'Try Test Bakery!',
    placeDetails: { id: 'p1', globalPlaceId: 'g1', name: 'Test Bakery', address: '1 Main St', photos: ['https://x/mine.jpg'], privateNotes: 'x' },
    mentionedPlaces: [{ placeId: 'p1', name: 'Test Bakery', startIndex: 4, endIndex: 15 }] });
  await put('suggestions', 's2', { userId: 'u1', createdAt: '2026-10-29', message: 'here',
    placeDetails: { id: 'p1', name: 'Test Bakery', photos: [] } });
  const { getSuggestionsByUser } = require('../../controllers/suggestionController');
  const res = respond();
  await getSuggestionsByUser({ user: { uid: 'u1' }, params: { userId: 'u1' } }, res);
  const [s1, s2] = res.body.data;
  expect(s1.placeDetails).toMatchObject({ name: "Sal's Bakery", address: '2 Main St, Charlotte, NC', photos: ['https://x/mine.jpg'] });
  expect(s1.mentionedPlaces[0].name).toBe('Test Bakery');
  // A card copied before the save was linked finds the venue through the save
  expect(s2.placeDetails).toMatchObject({ name: "Sal's Bakery", photos: ['https://x/cover.jpg'] });
});
