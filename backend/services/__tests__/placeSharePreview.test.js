// Security audit 2026-10-01: the public /place/:id share page used to print
// the name, address and photo of ANY place id. It now describes only what an
// anonymous viewer could see.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { publicPlacePreview } = require('../placeSharePreview');

const setup = async () => {
  const db = new FakeFirestore({ namespaced: true });
  const put = (col, id, data) => db.collection(col).doc(id).set(data);
  await put('circles', 'pub', { owner: 'o', privacy: 'public' });
  await put('circles', 'net', { owner: 'o', privacy: 'myNetwork' });
  await put('circles', 'priv', { owner: 'o', privacy: 'private', sharedWith: ['friend'] });
  await put('circles', 'gone', { owner: 'o', privacy: 'public', deletedAt: '2026-09-01' });
  const save = (circleId, extra = {}) => ({
    addedBy: 'o', circleId, name: ' Taco Spot ', address: '1 Main St', photos: [{ url: 'p.jpg' }], ...extra
  });
  await put('places', 'publicSave', save('pub'));
  await put('places', 'networkSave', save('net'));
  await put('places', 'privateSave', save('priv'));
  await put('places', 'deletedCircleSave', save('gone'));
  await put('places', 'privatePlaceInPublicCircle', save('pub', { privacy: 'private' }));
  await put('places', 'innerPlaceInPublicCircle', save('pub', { privacy: 'innerCircle' }));
  await put('places', 'deletedSave', save('pub', { deletedAt: '2026-09-01' }));
  // Venue records
  await put('globalPlaces', 'venuePublic', { name: 'Venue', address: '2 Main St' });
  await put('places', 'v1', save('priv', { globalPlaceId: 'venuePublic' }));
  await put('places', 'v2', save('pub', { globalPlaceId: 'venuePublic', photos: ['v.jpg'] }));
  await put('globalPlaces', 'venuePrivate', { name: "Mom's house", address: '3 Elm St' });
  await put('places', 'v3', save('priv', { globalPlaceId: 'venuePrivate' }));
  return db;
};

test('a save in a public circle is described', async () => {
  const db = await setup();
  expect(await publicPlacePreview(db, 'publicSave'))
    .toEqual({ name: 'Taco Spot', address: '1 Main St', photoUrl: 'p.jpg' });
});

test.each([
  'networkSave', 'privateSave', 'deletedCircleSave',
  'privatePlaceInPublicCircle', 'innerPlaceInPublicCircle', 'deletedSave', 'nope'
])('%s → generic page', async (id) => {
  const db = await setup();
  expect(await publicPlacePreview(db, id)).toBeNull();
});

test('a venue id is described only through a public save of it', async () => {
  const db = await setup();
  expect(await publicPlacePreview(db, 'venuePublic'))
    .toEqual({ name: 'Venue', address: '2 Main St', photoUrl: 'v.jpg' });
  expect(await publicPlacePreview(db, 'venuePrivate')).toBeNull();
});
