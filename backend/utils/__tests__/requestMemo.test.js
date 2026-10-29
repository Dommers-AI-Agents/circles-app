// One map/search request used to read the viewer's connections, Inner Circle
// lists and user doc two or three times. Inside a GET's memo they are read once.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
const reads = { connections: 0, users: 0, circles: 0 };
const realCollection = mockDb.collection.bind(mockDb);
mockDb.collection = (name) => {
  const col = realCollection(name);
  if (!(name in reads)) return col;
  // Count every query/doc read against the collection
  return new Proxy(col, {
    get(target, prop) {
      if (prop === 'where' || prop === 'doc') {
        reads[name]++;
      }
      const value = target[prop];
      return typeof value === 'function' ? value.bind(target) : value;
    }
  });
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { memo, withRequestMemo, requestMemoMiddleware, isMemoActive } = require('../requestMemo');
const { getConnectedUserIds, getAllowedCircleIds } = require('../networkAccess');
const { buildViewerContext } = require('../../services/viewerContext');

beforeAll(async () => {
  await mockDb.collection('users').doc('me').set({ following: ['fan'] });
  await mockDb.collection('connections').doc('c1').set({ userId: 'me', connectedUserId: 'bob', status: 'accepted' });
  await mockDb.collection('circles').doc('bobs').set({ owner: 'bob', privacy: 'public' });
});
beforeEach(() => { reads.connections = 0; reads.users = 0; reads.circles = 0; });

test('memo shares one computation per key and hands out copies', async () => {
  let calls = 0;
  await withRequestMemo(async () => {
    const a = await memo('k', async () => { calls++; return new Set(['x']); });
    a.add('mutated');
    const b = await memo('k', async () => { calls++; return new Set(['y']); });
    expect(calls).toBe(1);
    expect([...b]).toEqual(['x']);
  });
});

test('outside a request nothing is memoised; a failure is forgotten', async () => {
  let calls = 0;
  await memo('k', async () => { calls++; });
  await memo('k', async () => { calls++; });
  expect(calls).toBe(2);
  await withRequestMemo(async () => {
    await expect(memo('boom', async () => { throw new Error('x'); })).rejects.toThrow('x');
    await expect(memo('boom', async () => 'ok')).resolves.toBe('ok');
  });
});

test('the middleware memoises GETs only', () => {
  let active;
  requestMemoMiddleware({ method: 'GET' }, {}, () => { active = isMemoActive(); });
  expect(active).toBe(true);
  requestMemoMiddleware({ method: 'POST' }, {}, () => { active = isMemoActive(); });
  expect(active).toBe(false);
});

test('allowed circles + viewer context read connections and the user doc once per request', async () => {
  await withRequestMemo(async () => {
    const [{ circleIds }, ctx] = await Promise.all([getAllowedCircleIds('me'), buildViewerContext('me')]);
    expect(circleIds).toEqual(['bobs']);
    expect([...ctx.connections]).toEqual(['bob']);
    await getConnectedUserIds('me');
  });
  // Two directional connection queries, once
  expect(reads.connections).toBe(2);
});
