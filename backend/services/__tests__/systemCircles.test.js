// System circles are found by FLAG, never by name (Wes, 2026-10-31): a
// renamed one still works; a legacy name-only one is adopted and stamped; the
// backfill stamps the same circle the feature would pick.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const systemCircles = require('../systemCircles');
const { backfill } = require('../../tools/backfill-system-circle-flags');
const { DEFAULT_CIRCLES } = require('../../data/popularPlaces');

const put = (id, data) => mockDb.collection('circles').doc(id).set(data);
const circle = (id) => mockDb.rows('circles').get(id);

beforeEach(() => { mockDb.rows('circles').clear(); });

describe('matching', () => {
  test('a flagged circle is its kind whatever it is called', () => {
    expect(systemCircles.isKind({ name: 'Stores', systemKind: 'followedPlaces' }, 'followedPlaces')).toBe(true);
    expect(systemCircles.isKind({ name: 'Where I went', isCheckInCircle: true }, 'checkIns')).toBe(true);
    expect(systemCircles.isKind({ name: 'Pups', isDogSpotsCircle: true }, 'dogSpots')).toBe(true);
    expect(systemCircles.isKind({ name: 'Camera roll', isImportCircle: true, importSource: 'photos' }, 'photoPlaces')).toBe(true);
    expect(systemCircles.kindOf({ name: 'Local faves', systemKind: 'favoriteLocal' })).toBe('favoriteLocal');
  });

  test('legacy name only counts for docs with no flag; starters also need isDefaultCircle', () => {
    expect(systemCircles.isKind({ name: 'Places I Follow' }, 'followedPlaces')).toBe(true);
    expect(systemCircles.isKind({ name: 'Places I Follow', systemKind: 'checkIns' }, 'followedPlaces')).toBe(false);
    expect(systemCircles.isKind({ name: 'Want to Try' }, 'wantToTry')).toBe(false);
    expect(systemCircles.isKind({ name: 'Want to Try', isDefaultCircle: true }, 'wantToTry')).toBe(true);
    expect(systemCircles.isKind({ name: 'Places I Follow', isCheckInCircle: true }, 'followedPlaces')).toBe(false);
  });

  test('app-made collections and starter circles', () => {
    expect(systemCircles.isAppMadeCollection({ name: 'Renamed', systemKind: 'followedPlaces' })).toBe(true);
    expect(systemCircles.isAppMadeCollection({ name: 'Eateries' })).toBe(false);
    expect(systemCircles.isStarterCircle({ name: 'Trips', isDefaultCircle: true })).toBe(true);
    expect(systemCircles.isStarterCircle({ name: 'Vacation' })).toBe(true);
    expect(systemCircles.isStarterCircle({ name: 'Eateries' })).toBe(false);
  });

  test('onboarding templates carry their flag', () => {
    expect(DEFAULT_CIRCLES.map((t) => t.systemKind || null)).toEqual(['wantToTry', 'favoriteLocal', null]);
    expect(systemCircles.flagFields('checkIns')).toEqual({ systemKind: 'checkIns', isCheckInCircle: true });
    expect(systemCircles.flagFields('favoriteLocal')).toEqual({ systemKind: 'favoriteLocal' });
  });
});

describe('findOwned', () => {
  test('finds the system circle after the user renames it', async () => {
    await put('f1', { owner: 'u1', name: 'Shops I watch', systemKind: 'followedPlaces', isFollowedPlacesCircle: true, createdAt: '2026-01-01' });
    await put('x', { owner: 'u1', name: 'Places I Follow', createdAt: '2026-05-01' }); // their own, newer, unflagged
    const found = await systemCircles.findOwned('u1', 'followedPlaces');
    expect(found.id).toBe('f1');
    expect(circle('x').systemKind).toBeUndefined();
  });

  test('a renamed starter (no boolean) is found through the owner scan', async () => {
    await put('w1', { owner: 'u1', name: 'Someday', systemKind: 'wantToTry', isDefaultCircle: true });
    expect((await systemCircles.findOwned('u1', 'wantToTry')).id).toBe('w1');
  });

  test('a legacy name-only circle is matched and stamped (one write)', async () => {
    await put('c-empty', { owner: 'u1', name: 'Check-in Places', isCheckInCircle: false, places: [], createdAt: '2026-01-01' });
    await put('c-full', { owner: 'u1', name: 'Check-in Places', isCheckInCircle: false, places: ['p1', 'p2'], createdAt: '2026-02-01' });
    const found = await systemCircles.findOwned('u1', 'checkIns');
    expect(found.id).toBe('c-full');
    expect(circle('c-full')).toMatchObject({ systemKind: 'checkIns', isCheckInCircle: true });
    expect(circle('c-empty').systemKind).toBeUndefined();
    // Renamed afterwards: still found, by flag
    await mockDb.collection('circles').doc('c-full').update({ name: 'Been there' });
    expect((await systemCircles.findOwned('u1', 'checkIns')).id).toBe('c-full');
  });

  test('a boolean-flagged circle gets systemKind too; deleted and other owners never count', async () => {
    await put('d0', { owner: 'u1', name: 'Dog spots', isDogSpotsCircle: true, deletedAt: '2026-03-01' });
    await put('d1', { owner: 'u1', name: 'Pups', isDogSpotsCircle: true });
    await put('d2', { owner: 'u2', name: 'Dog spots', systemKind: 'dogSpots', isDogSpotsCircle: true });
    expect((await systemCircles.findOwned('u1', 'dogSpots')).id).toBe('d1');
    expect(circle('d1').systemKind).toBe('dogSpots');
    expect(await systemCircles.findOwned('u3', 'dogSpots')).toBeNull();
  });
});

describe('backfill', () => {
  const seed = async () => {
    await put('a', { owner: 'u1', name: 'Places I Follow', isFollowedPlacesCircle: false, createdAt: '2026-01-01' });
    await put('b', { owner: 'u1', name: 'Want to Try', isDefaultCircle: true });
    await put('c', { owner: 'u1', name: 'Want to Try' }); // not a starter → never adopted
    await put('d', { owner: 'u2', name: 'Places from my photos', isImportCircle: true, importSource: 'photos' });
    await put('e', { owner: 'u2', name: 'Pins', systemKind: 'checkIns', isCheckInCircle: true });
  };

  test('DRY_RUN changes nothing and counts per kind', async () => {
    await seed();
    const before = JSON.stringify([...mockDb.rows('circles').entries()]);
    const counts = await backfill({ dryRun: true, log: () => {} });
    expect(JSON.stringify([...mockDb.rows('circles').entries()])).toBe(before);
    expect(counts.followedPlaces).toMatchObject({ stamped: 1, fromName: 1 });
    expect(counts.wantToTry).toMatchObject({ stamped: 1, fromName: 1 });
    expect(counts.photoPlaces).toMatchObject({ stamped: 1, fromMarker: 1 });
    expect(counts.checkIns).toMatchObject({ alreadyFlagged: 1, stamped: 0 });
  });

  test('stamps what the feature would pick, and a second run stamps nothing', async () => {
    await seed();
    await backfill({ log: () => {} });
    expect(circle('a')).toMatchObject({ systemKind: 'followedPlaces', isFollowedPlacesCircle: true });
    expect(circle('b').systemKind).toBe('wantToTry');
    expect(circle('c').systemKind).toBeUndefined();
    expect(circle('d').systemKind).toBe('photoPlaces');
    const again = await backfill({ log: () => {} });
    expect(Object.values(again).every((c) => c.stamped === 0)).toBe(true);
  });
});
