// "Places your people love": what counts, what's hidden, how it's ranked.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const mockConnections = new Set();
jest.mock('../../utils/networkAccess', () => ({
  getConnectedUserIds: jest.fn(async () => mockConnections),
  getInnerCircleGrantorLists: jest.fn(async () => new Map()),
  getInnerCircleGrantorIds: jest.fn(async () => new Set())
}));
jest.mock('../viewerContext', () => {
  const actual = jest.requireActual('../viewerContext');
  return {
    ...actual,
    buildViewerContext: jest.fn(async (viewerId) => actual.makeViewerContext({
      viewerId, connections: [...mockConnections], following: [], innerCircleLists: new Map()
    }))
  };
});

const loved = require('../networkLovedPlaces');

describe('ranking (pure)', () => {
  test('two or more distinct savers, most-saved first, newest saver first on the card', () => {
    const rows = loved.rankVenues([
      { globalPlaceId: 'a', addedBy: 'x', createdAt: '2026-09-01' },
      { globalPlaceId: 'a', addedBy: 'y', createdAt: '2026-09-20' },
      { globalPlaceId: 'a', addedBy: 'y', createdAt: '2026-09-02' }, // same saver twice = one
      { globalPlaceId: 'b', addedBy: 'x', createdAt: '2026-09-25' },
      { globalPlaceId: 'b', addedBy: 'y', createdAt: '2026-09-10' },
      { globalPlaceId: 'b', addedBy: 'z', createdAt: '2026-09-11' },
      { globalPlaceId: 'c', addedBy: 'x', createdAt: '2026-09-29' },
      { globalPlaceId: null, addedBy: 'x' }
    ]);
    expect(rows.map((r) => r.globalPlaceId)).toEqual(['b', 'a']);
    expect(rows[0].saverIds).toEqual(['x', 'z', 'y']);
    expect(rows[1].saverIds).toEqual(['y', 'x']);
  });

  test('check-in and Places I Follow circles are not someone loving a place', () => {
    expect(loved.isSystemCircle({ isCheckInCircle: true })).toBe(true);
    expect(loved.isSystemCircle({ name: 'Places I Follow' })).toBe(true);
    expect(loved.isSystemCircle({ name: 'Pizza' })).toBe(false);
  });
});

describe('forViewer', () => {
  beforeEach(() => {
    ['places', 'circles', 'users', 'globalPlaces'].forEach((c) => mockDb.rows(c).clear());
    mockConnections.clear();
    loved._cache.clear();
  });

  const circle = (id, owner, extra = {}) => mockDb.collection('circles').doc(id).set({ owner, name: id, privacy: 'myNetwork', ...extra });
  const save = (id, addedBy, gp, circleId, extra = {}) => mockDb.collection('places').doc(id).set({ addedBy, globalPlaceId: gp, circleId, createdAt: '2026-09-2' + id.length, ...extra });

  test('only saves the viewer may see count; check-ins, deleted and blocked people never do', async () => {
    ['brit', 'sal', 'joe', 'blocked'].forEach((id) => mockConnections.add(id));
    await mockDb.collection('users').doc('wes').set({ blockedUsers: ['blocked'] });
    await mockDb.collection('users').doc('brit').set({ displayName: 'Brit' });
    await mockDb.collection('users').doc('sal').set({ displayName: 'Sal' });
    await mockDb.collection('globalPlaces').doc('gp1').set({ name: 'Il Posto', category: 'restaurant', photos: [{ id: 'p', url: 'https://x/p.jpg' }] });
    await mockDb.collection('globalPlaces').doc('gp2').set({ name: 'Secret Spot' });
    await circle('cb', 'brit'); await circle('cs', 'sal'); await circle('cj', 'joe');
    await circle('cpriv', 'joe', { privacy: 'private' });
    await circle('ccheck', 'joe', { isCheckInCircle: true });
    await circle('cblk', 'blocked');

    await save('a', 'brit', 'gp1', 'cb');
    await save('bb', 'sal', 'gp1', 'cs');
    await save('ccc', 'joe', 'gp1', 'cj', { deletedAt: '2026-09-29' }); // unsaved — doesn't count
    await save('d', 'joe', 'gp2', 'cpriv');                              // private circle
    await save('ee', 'joe', 'gp2', 'ccheck');                            // a check-in
    await save('fff', 'blocked', 'gp2', 'cblk');                         // blocked
    await save('g', 'brit', 'gp2', 'cb', { privacy: 'private' });        // private place
    await save('hhhh', 'blocked', 'gp1', 'cblk');                      // blocked person, counted place
    await save('mine', 'wes', 'gp1', 'cw');

    const rows = await loved.forViewer('wes');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ globalPlaceId: 'gp1', name: 'Il Posto', saverCount: 2, viewerSaved: true, photo: 'https://x/p.jpg' });
    expect(rows[0].savers.map((s) => s.displayName).sort()).toEqual(['Brit', 'Sal']);
  });

  test('nobody connected: nothing, without reading places', async () => {
    expect(await loved.forViewer('lonely')).toEqual([]);
  });
});

