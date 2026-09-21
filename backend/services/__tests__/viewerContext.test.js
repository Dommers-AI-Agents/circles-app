// The relationship bundle every visibility decision reads. The one rule with
// teeth: an Inner Circle grant only counts while the grantor is a connection.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const mockNetwork = { connections: new Set(), grantors: new Set(), lists: new Map() };
jest.mock('../../utils/networkAccess', () => ({
  getConnectedUserIds: jest.fn(async () => mockNetwork.connections),
  getInnerCircleGrantorIds: jest.fn(async () => mockNetwork.grantors),
  getInnerCircleGrantorLists: jest.fn(async () => mockNetwork.lists)
}));

const { makeViewerContext, buildViewerContext } = require('../viewerContext');
const { COLLECTIONS } = require('../../models/FirestoreModels');

test('makeViewerContext normalises ids and intersects grantors with connections', () => {
  const ctx = makeViewerContext({
    viewerId: 'me',
    connections: ['a', 'apple.b.com', null, ''],
    following: new Set(['c']),
    innerCircleGrantors: ['a', 'zed', 'b']
  });
  expect(ctx.viewerId).toBe('me');
  expect([...ctx.connections]).toEqual(['a', 'b']);
  expect([...ctx.following]).toEqual(['c']);
  expect([...ctx.innerCircleGrantors]).toEqual(['a', 'b']); // zed never connected
});

test('an anonymous viewer gets empty sets and no reads', async () => {
  const ctx = await buildViewerContext(null);
  expect(ctx.viewerId).toBeNull();
  expect(ctx.connections.size + ctx.following.size + ctx.innerCircleGrantors.size).toBe(0);
  expect(require('../../utils/networkAccess').getConnectedUserIds).not.toHaveBeenCalled();
});

test('buildViewerContext reads following from the user doc and tolerates a missing doc', async () => {
  mockNetwork.connections = new Set(['a']);
  mockNetwork.lists = new Map([['a', new Set(['family'])], ['gone', new Set(['x'])]]);
  mockDb.rows(COLLECTIONS.USERS).set('me', { following: ['f1', 'f2'] });
  const ctx = await buildViewerContext('me');
  expect([...ctx.following]).toEqual(['f1', 'f2']);
  expect([...ctx.innerCircleGrantors]).toEqual(['a']);
  const missing = await buildViewerContext('ghost');
  expect(missing.following.size).toBe(0);
  expect([...missing.connections]).toEqual(['a']);
});

test('a named list survives only while its owner is still a connection', () => {
  const ctx = makeViewerContext({
    viewerId: 'me',
    connections: ['a'],
    innerCircleLists: new Map([
      ['a', new Set(['family', 'gym'])],
      ['zed', new Set(['anything'])]      // no longer a connection
    ])
  });
  // Owners come from the map when the caller doesn't pass them separately.
  expect([...ctx.innerCircleGrantors]).toEqual(['a']);
  expect([...(ctx.innerCircleLists.get('a') || [])].sort()).toEqual(['family', 'gym']);
  expect(ctx.innerCircleLists.has('zed')).toBe(false);
});

test('a caller who brings no per-list map gets an empty one, not a missing one', () => {
  const ctx = makeViewerContext({ viewerId: 'me', connections: ['a'], innerCircleGrantors: ['a'] });
  expect(ctx.innerCircleLists.size).toBe(0);
  expect([...ctx.innerCircleGrantors]).toEqual(['a']);
});
