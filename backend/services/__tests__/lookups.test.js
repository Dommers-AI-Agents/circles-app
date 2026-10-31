// The shared "who / which circle / which store is it now" lookups and the
// single venue-details write path (Wes, 2026-10-31: one source for every
// data point).
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

const { fetchUsersById, withCurrentUser } = require('../userLookup');
const { fetchCirclesById } = require('../circleLookup');
const { applyVenueDetails, storeUpdatesFor } = require('../venueDetailsService');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(() => {
  for (const name of ['users', 'circles', 'globalPlaces', 'places', 'stickerVenues']) mockDb.rows(name).clear();
});

test('users: current name and photo, never email; stored values only when the account is gone', async () => {
  await put('users', 'u1', { displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg', email: 'sal@example.com' });
  const users = await fetchUsersById(['u1', 'u1', 'gone', null]);
  expect(users.get('u1')).toMatchObject({ id: 'u1', displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
  expect(users.get('u1').email).toBeUndefined();
  const row = { userId: 'u1', userName: 'Salvatore', userPhoto: 'https://x/old.jpg', text: 'hi' };
  expect(withCurrentUser(row, users, { id: 'userId', name: 'userName', photo: 'userPhoto' }))
    .toEqual({ userId: 'u1', userName: 'Sal Sgroi', userPhoto: 'https://x/new.jpg', text: 'hi' });
  const orphan = { userId: 'gone', userName: 'Old Name' };
  expect(withCurrentUser(orphan, users, { id: 'userId', name: 'userName' })).toBe(orphan);
});

test('circles: current name and cover; deleted circles are absent', async () => {
  await put('circles', 'c1', { name: 'Eateries', coverImage: 'https://x/c.jpg', category: 'food', privacy: 'public', owner: 'u1' });
  await put('circles', 'c2', { name: 'Trash', deletedAt: '2026-10-01' });
  const circles = await fetchCirclesById(['c1', 'c2', 'nope']);
  expect(circles.get('c1')).toMatchObject({ name: 'Eateries', coverImage: 'https://x/c.jpg' });
  expect(circles.has('c2')).toBe(false);
  expect(circles.has('nope')).toBe(false);
});

test('the store mirrors name, address, map point and category — never its slug', () => {
  expect(storeUpdatesFor({ name: 'Sal', address: '1 Main St', location: { type: 'Point', coordinates: [-80.8, 35.2] }, category: 'cafe', description: 'x' }))
    .toEqual({ placeName: 'Sal', venueName: 'Sal', placeAddress: '1 Main St', location: { lat: 35.2, lng: -80.8 }, category: 'cafe' });
  expect(storeUpdatesFor({ description: 'only' })).toEqual({});
});

test('one write path: a move updates the venue, every save and the store, with the city re-derived', async () => {
  await put('globalPlaces', 'g1', { name: 'Shop', address: '1 Main St, Asbury Park, NJ 07712, USA', category: 'retail',
    location: { type: 'Point', coordinates: [-74.01, 40.22] }, city: 'Asbury Park', stateCode: 'NJ' });
  await put('places', 'p1', { globalPlaceId: 'g1', name: 'Shop', addedBy: 'u1', city: 'Asbury Park' });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Shop', placeAddress: '1 Main St, Asbury Park, NJ 07712, USA',
    location: { lat: 40.22, lng: -74.01 }, category: 'retail', slug: 'shop' });

  await applyVenueDetails('g1', { address: '1540 S Church St, Charlotte, NC 28203, USA',
    location: { type: 'Point', coordinates: [-80.86, 35.21] }, category: 'cafe' });

  const g = mockDb.rows('globalPlaces').get('g1');
  expect(g).toMatchObject({ address: '1540 S Church St, Charlotte, NC 28203, USA', category: 'cafe', stateCode: 'NC' });
  expect(mockDb.rows('places').get('p1')).toMatchObject({ address: g.address, category: 'cafe', stateCode: 'NC', city: g.city });
  expect(mockDb.rows('stickerVenues').get('v1')).toMatchObject({
    placeAddress: g.address, location: { lat: 35.21, lng: -80.86 }, category: 'cafe', venueName: 'Shop', slug: 'shop'
  });
});
