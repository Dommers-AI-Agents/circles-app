// Home search's network source: "which venues matching this text has someone
// in my network saved?" answered by one catalog read + one chunked save
// lookup, instead of one request per network circle (Wes, 2026-10-28: 239
// circles meant 239 requests, and Test Bakery showed up 30 s after typing).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  admin: { firestore: { FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue } },
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../utils/networkAccess', () => ({
  getAllowedCircleIds: jest.fn(async () => ({ circleIds: ['friends-circle', 'own-circle'] })),
  getConnectedUserIds: jest.fn(async () => ['friend']),
  getInnerCircleGrantorLists: jest.fn(async () => new Map())
}));
jest.mock('../../services/viewerContext', () => {
  const { makeViewerContext } = jest.requireActual('../../services/viewerContext');
  return {
    makeViewerContext,
    buildViewerContext: jest.fn(async (viewerId) => makeViewerContext({ viewerId, connections: ['friend'], following: ['friend'] }))
  };
});
jest.mock('../../services/placeReadService', () => ({
  fetchGlobalSocialMap: jest.fn(async () => new Map()),
  overlayVenueFields: (place) => place
}));

const { searchNetworkPlaces } = require('../networkPlacesController');
const { searchGlobalPlaces } = require('../../services/globalPlaceSearch');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const tokens = (name) => {
  const out = new Set();
  for (const word of name.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean)) {
    for (let i = 1; i <= word.length; i++) out.add(word.slice(0, i));
  }
  return [...out];
};
const venue = (id, name, lng, lat, qualityScore) =>
  put('globalPlaces', id, { name, searchTokens: tokens(name), nameLower: name.toLowerCase(), qualityScore,
    location: { type: 'Point', coordinates: [lng, lat] } });
// Charlotte: the viewer stands at South End
const ME = { lat: 35.2171, lng: -80.8572 };

beforeEach(async () => {
  for (const name of ['users', 'globalPlaces', 'places']) mockDb.rows(name).clear();
  await put('users', 'friend', { displayName: 'Friend', photoURL: 'https://x/f.jpg', email: 'friend@x.com' });
  await venue('g-test', 'Test Bakery (Demo)', -80.8592, 35.2169, 0.41);     // 190 m away
  await venue('g-amelie', "Amélie's French Bakery", -80.8079, 35.2517, 0.52); // ~6 km
  await venue('g-colvitto', "Colvitto's Pizza & Bakery", -71.4837, 41.4283, 0.62); // Rhode Island
  await venue('g-donut', 'The Salty Donut', -80.8560, 35.2190, 0.70);        // no "bakery" in the name
  // Saves: a friend's followCircle save of Test Bakery, my own save of
  // Amélie's, a stranger's save in a circle I can't see, a deleted save
  await put('places', 'save-test', { globalPlaceId: 'g-test', addedBy: 'friend', circleId: 'friends-circle',
    privacy: 'followCircle', name: 'Test Bakery (Demo)', privateNotes: 'secret' });
  await put('places', 'save-amelie-mine', { globalPlaceId: 'g-amelie', addedBy: 'me', circleId: 'own-circle', name: "Amélie's" });
  await put('places', 'save-amelie-stranger', { globalPlaceId: 'g-amelie', addedBy: 'stranger', circleId: 'hidden-circle', name: "Amélie's" });
  await put('places', 'save-amelie-friend', { globalPlaceId: 'g-amelie', addedBy: 'friend', circleId: 'friends-circle', name: "Amélie's" });
  await put('places', 'save-deleted', { globalPlaceId: 'g-test', addedBy: 'friend', circleId: 'friends-circle', name: 'gone', deletedAt: 'x' });
  await put('places', 'save-private', { globalPlaceId: 'g-amelie', addedBy: 'friend', circleId: 'friends-circle', name: 'mine only', privacy: 'private' });
});

test('catalog search: every token must match, nearest first inside the radius', async () => {
  const hits = await searchGlobalPlaces({ query: 'Bakery', lat: ME.lat, lng: ME.lng, radiusKm: 80, limit: 50 });
  expect(hits.map(h => h.id)).toEqual(['g-test', 'g-amelie']);
  expect(hits[0].searchTokens).toBeUndefined();
  const two = await searchGlobalPlaces({ query: 'french bak', limit: 50 });
  expect(two.map(h => h.id)).toEqual(['g-amelie']);
});

test('network search returns only visible network saves of matching venues, nearest venue first', async () => {
  const r = res();
  await searchNetworkPlaces({ user: { uid: 'me' }, query: { query: 'Bakery', lat: String(ME.lat), lng: String(ME.lng) } }, r);
  expect(r.status).toHaveBeenCalledWith(200);
  const body = r.json.mock.calls[0][0];
  expect(body.success).toBe(true);
  expect(body.places.map(p => p.id)).toEqual(['save-test', 'save-amelie-friend']);
  // the friend's private notes never leave the server; the adder is summarised
  expect(body.places[0].privateNotes).toBeUndefined();
  expect(body.places[0].addedByUser).toEqual(expect.objectContaining({ displayName: 'Friend' }));
  expect(body.places[0].addedByUser.email).toBeUndefined();
});

test('network search without text is refused; no venue match means an empty list', async () => {
  const r1 = res();
  await searchNetworkPlaces({ user: { uid: 'me' }, query: {} }, r1);
  expect(r1.status).toHaveBeenCalledWith(400);
  const r2 = res();
  await searchNetworkPlaces({ user: { uid: 'me' }, query: { query: 'Sushi' } }, r2);
  expect(r2.json.mock.calls[0][0]).toEqual({ success: true, places: [], total: 0, hasMore: false });
});
