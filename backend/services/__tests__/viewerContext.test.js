// The relationship bundle every visibility decision reads. The one rule with
// teeth: an Inner Circle grant only counts while the grantor is a connection.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const mockNetwork = { connections: new Set(), grantors: new Set() };
jest.mock('../../utils/networkAccess', () => ({
  getConnectedUserIds: jest.fn(async () => mockNetwork.connections),
  getInnerCircleGrantorIds: jest.fn(async () => mockNetwork.grantors)
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
  mockNetwork.grantors = new Set(['a', 'gone']);
  mockDb.rows(COLLECTIONS.USERS).set('me', { following: ['f1', 'f2'] });
  const ctx = await buildViewerContext('me');
  expect([...ctx.following]).toEqual(['f1', 'f2']);
  expect([...ctx.innerCircleGrantors]).toEqual(['a']);
  const missing = await buildViewerContext('ghost');
  expect(missing.following.size).toBe(0);
  expect([...missing.connections]).toEqual(['a']);
});
