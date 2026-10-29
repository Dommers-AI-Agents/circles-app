// Distance-first catalog search: a near venue is found however many better
// rated venues share the word elsewhere (the old path cut the platform-wide
// quality top-N before the radius, so local results fell out as the catalog grew).
const geofire = require('geofire-common');
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { buildSearchTokens } = require('../../utils/searchTokens');
const { searchGlobalPlaces, searchGlobalPlacesForText } = require('../globalPlaceSearch');

const CLT = { lat: 35.2271, lng: -80.8431 };
const venue = (name, lat, lng, extra = {}) => ({
  name,
  searchTokens: buildSearchTokens(name),
  location: { type: 'Point', coordinates: [lng, lat] },
  geohash: geofire.geohashForLocation([lat, lng]),
  category: 'restaurant',
  qualityScore: 1,
  ...extra
});

const seed = async (db, rows) => {
  for (const [id, data] of Object.entries(rows)) await db.collection('globalPlaces').doc(id).set(data);
};

describe('searchGlobalPlaces (distance-first)', () => {
  let db;
  beforeEach(() => { db = new FakeFirestore({ namespaced: true }); });

  test('a near low-quality venue beats far high-quality ones even with a tiny limit', async () => {
    const rows = { near: venue('Corner Pizza', CLT.lat + 0.01, CLT.lng, { qualityScore: 0.1 }) };
    for (let i = 0; i < 20; i++) rows[`far${i}`] = venue(`Famous Pizza ${i}`, 40.7 + i * 0.01, -74.0, { qualityScore: 9 });
    await seed(db, rows);
    const out = await searchGlobalPlaces({ query: 'pizza', lat: CLT.lat, lng: CLT.lng, radiusKm: 50, limit: 5, db });
    expect(out.map(p => p.id)).toEqual(['near']);
    expect(out[0]).not.toHaveProperty('searchTokens');
    expect(out[0]).not.toHaveProperty('geohash');
  });

  test('nearest first; every query word must match; merged and deleted venues are skipped', async () => {
    await seed(db, {
      a: venue('Pizza Palace', CLT.lat + 0.05, CLT.lng),
      b: venue('Pizza Palace Express', CLT.lat + 0.01, CLT.lng),
      c: venue('Pizza Hut', CLT.lat + 0.001, CLT.lng),
      merged: venue('Pizza Palace', CLT.lat, CLT.lng, { mergedInto: 'a' }),
      gone: venue('Pizza Palace', CLT.lat, CLT.lng, { deletedAt: '2026-10-01' })
    });
    const out = await searchGlobalPlaces({ query: 'pizza pal', lat: CLT.lat, lng: CLT.lng, radiusKm: 50, limit: 50, db });
    expect(out.map(p => p.id)).toEqual(['b', 'a']);
  });

  test('category words search the category near the origin', async () => {
    await seed(db, {
      beans: venue('Beans & Co', CLT.lat + 0.01, CLT.lng, { category: 'cafe' }),
      farCafe: venue('Far Cafe', 47.6, -122.3, { category: 'cafe' }),
      diner: venue('Diner', CLT.lat, CLT.lng)
    });
    const out = await searchGlobalPlacesForText({ query: 'coffee', lat: CLT.lat, lng: CLT.lng, radiusKm: 50, limit: 50, db });
    expect(out.map(p => p.id)).toEqual(['beans']);
  });

  test('a venue not yet stamped with a geohash still comes back via the quality path', async () => {
    const { geohash, ...unstamped } = venue('Old Bakery', CLT.lat, CLT.lng); // eslint-disable-line no-unused-vars
    await seed(db, { old: unstamped });
    const out = await searchGlobalPlaces({ query: 'bakery', lat: CLT.lat, lng: CLT.lng, radiusKm: 50, limit: 50, db });
    expect(out.map(p => p.id)).toEqual(['old']);
  });

  test('no origin: quality order, live venues only', async () => {
    await seed(db, {
      low: venue('Taco Stand', 1, 1, { qualityScore: 1 }),
      high: venue('Taco Shop', 2, 2, { qualityScore: 5 }),
      gone: venue('Taco Gone', 3, 3, { qualityScore: 9, deletedAt: 'x' })
    });
    const out = await searchGlobalPlaces({ query: 'taco', limit: 10, db });
    expect(out.map(p => p.id)).toEqual(['high', 'low']);
  });
});
