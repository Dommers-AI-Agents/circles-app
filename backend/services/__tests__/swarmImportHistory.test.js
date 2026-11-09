// Swarm import (Wes, 2026-11-09): every venue's check-in history comes over
// with it, onto a new save or one the person already had, silently, and a
// second import of the same export never double-counts.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
// Linking gives each save a venue named after the save
jest.mock('../globalPlaceResolver', () => ({
  ensureGlobalPlaceLink: jest.fn(async (snap) => {
    const gpid = `gp-${snap.id}`;
    await mockDb.collection('places').doc(snap.id).set({ globalPlaceId: gpid }, { merge: true });
    return gpid;
  }),
  findCanonicalByNameAndLocation: jest.fn(async () => null)
}));
jest.mock('../googleEnrichment', () => ({ enrichSaveFromGoogle: jest.fn(async () => false) }));
jest.mock('../subscriptionLimitService', () => ({
  canImport: jest.fn(async () => ({ canImport: true })),
  canCreateCircle: jest.fn(async () => ({ canCreate: true })),
  checkPlaceLimit: jest.fn(async () => ({ canAdd: true }))
}));

const importService = require('../importService');
const stats = require('../checkInStatsService');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const ME = 'me';

const statsFor = (gpid) => mockDb.collection(COLLECTIONS.USERS).doc(ME)
  .collection(COLLECTIONS.CHECK_IN_STATS).doc(gpid).get().then((s) => (s.exists ? s.data() : null));

const ilios = {
  name: 'Ilios Crafted Greek', lat: 35.21696, lng: -80.85934, address: '1 Main St, Charlotte, NC, 28202, United States',
  category: 'restaurant', sourceExternalId: '5ecea99334eba80008b02265',
  sourceUrl: 'https://app.foursquare.com/v/ilios-crafted-greek/5ecea99334eba80008b02265',
  checkIns: { count: 12, firstAt: '2019-03-02T18:00:00.000Z', lastAt: '2026-11-07T12:06:39.000Z' }
};
const swarmImport = (places) => importService.executeImport(ME, { source: 'swarm', lists: [{ name: 'Swarm check-ins', places }] });

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
  mockDb.collection(COLLECTIONS.USERS).doc(ME).set({ displayName: 'Me' });
});

test('a new place brings its check-in history', async () => {
  const result = await swarmImport([ilios]);
  expect(result.results[0]).toMatchObject({ created: 1, historyRecorded: 1 });
  const [placeId] = [...mockDb.rows(COLLECTIONS.PLACES).keys()];
  const bucket = await statsFor(`gp-${placeId}`);
  expect(bucket.imported.swarm).toEqual({ count: 12, firstCheckInAt: '2019-03-02T18:00:00.000Z', lastCheckInAt: '2026-11-07T12:06:39.000Z' });
  expect(stats.toApi(bucket)).toEqual({ count: 12, firstCheckInAt: '2019-03-02T18:00:00.000Z', lastCheckInAt: '2026-11-07T12:06:39.000Z', importedCount: 12 });
});

test('importing the same export twice never double-counts', async () => {
  await swarmImport([ilios]);
  const second = await swarmImport([ilios]);
  expect(second.results[0]).toMatchObject({ created: 0, skippedDuplicates: 1, historyRecorded: 1 });
  const [placeId] = [...mockDb.rows(COLLECTIONS.PLACES).keys()];
  expect((await statsFor(`gp-${placeId}`)).imported.swarm.count).toBe(12);
});

test('a place already saved gets the history (sent history-only), and FavCircles check-ins add to it', async () => {
  mockDb.collection(COLLECTIONS.PLACES).doc('mine').set({ addedBy: ME, name: 'Ilios Crafted Greek', circleId: 'c1',
    globalPlaceId: 'venue-ilios', location: { type: 'Point', coordinates: [-80.8593, 35.2170] }, deletedAt: null });
  // Two check-ins already made in FavCircles
  await mockDb.collection(COLLECTIONS.USERS).doc(ME).collection(COLLECTIONS.CHECK_IN_STATS).doc('venue-ilios')
    .set({ count: 2, firstCheckInAt: '2026-10-01T00:00:00.000Z', lastCheckInAt: '2026-11-08T00:00:00.000Z' });
  const result = await swarmImport([{ ...ilios, historyOnly: true }]);
  expect(result.results[0]).toMatchObject({ created: 0, skippedDuplicates: 1, historyRecorded: 1 });
  expect(mockDb.rows(COLLECTIONS.PLACES).size).toBe(1); // nothing new saved
  expect(stats.toApi(await statsFor('venue-ilios'))).toEqual({
    count: 14, firstCheckInAt: '2019-03-02T18:00:00.000Z', lastCheckInAt: '2026-11-08T00:00:00.000Z', importedCount: 12
  });
});

test('a history-only row that matches nothing is not saved', async () => {
  const result = await swarmImport([{ ...ilios, historyOnly: true }]);
  expect(result.results[0]).toMatchObject({ created: 0 });
  expect(mockDb.rows(COLLECTIONS.PLACES).size).toBe(0);
});

test('history is only for Swarm, and bad history is ignored', () => {
  expect(stats.cleanImportedHistory({ count: 0, firstAt: '2020-01-01' })).toBeNull();
  expect(stats.cleanImportedHistory({ count: 3 })).toBeNull();
  expect(stats.cleanImportedHistory({ count: 2.5, firstAt: '2020-01-01' })).toBeNull();
  // Out of order dates are put right
  expect(stats.cleanImportedHistory({ count: 2, firstAt: '2024-01-01T00:00:00Z', lastAt: '2020-01-01T00:00:00Z' }))
    .toEqual({ count: 2, firstCheckInAt: '2020-01-01T00:00:00.000Z', lastCheckInAt: '2024-01-01T00:00:00.000Z' });
});

test('the preview carries each Swarm venue\'s history back to the app', async () => {
  const { preview } = await importService.prepareImport(ME, { source: 'swarm', lists: [{ name: 'Swarm check-ins', places: [ilios] }] });
  expect(preview.lists[0].places[0].checkIns).toEqual({ count: 12, firstAt: '2019-03-02T18:00:00.000Z', lastAt: '2026-11-07T12:06:39.000Z' });
  const google = await importService.prepareImport(ME, { source: 'google_maps', lists: [{ name: 'Saved', places: [ilios] }] });
  expect(google.preview.lists[0].places[0].checkIns).toBeNull();
});

test('two branches of a chain with no address yet stay two places, pinned and queued for their address', async () => {
  const branch = (id, lat) => ({ name: 'Starbucks', lat, lng: -80.85, sourceExternalId: id, category: 'cafe',
    checkIns: { count: 1, firstAt: '2020-01-01T00:00:00Z', lastAt: '2020-01-01T00:00:00Z' } });
  const { preview } = await importService.prepareImport(ME, { source: 'swarm', lists: [{ name: 'Swarm check-ins', places: [branch('a', 35.20), branch('b', 35.23)] }] });
  expect(preview.lists[0].places.map((p) => [p.status, p.address])).toEqual([['new', 'Address pending'], ['new', 'Address pending']]);
  const result = await swarmImport(preview.lists[0].places);
  expect(result.results[0]).toMatchObject({ created: 2 });
  const saves = [...mockDb.rows(COLLECTIONS.PLACES).values()];
  expect(saves.every((p) => p.location && p.needsResolution === true && p.address === 'Address pending')).toBe(true);
});
