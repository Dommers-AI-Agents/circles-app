// Owner resolution is the difference between "Shared by Brittany C" and
// "Shared by Unknown", and between showing a deleted account's circle and
// hiding it. These lock in both.

const mockGet = jest.fn();
const mockDoc = jest.fn();
const mockCollection = jest.fn();

jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: mockCollection })
}));

jest.mock('../../models/FirestoreModels', () => ({
  COLLECTIONS: { USERS: 'users' },
  serializeDoc: (doc) => ({ id: doc.id, ...doc.data() })
}));

const makeDoc = (id, data) => ({ id, exists: true, data: () => data });
const missingDoc = { exists: false, data: () => ({}) };

describe('ownerResolver', () => {
  let resolver;

  beforeEach(() => {
    jest.resetModules();
    mockCollection.mockReset();
    mockDoc.mockReset();
    mockGet.mockReset();
    resolver = require('../ownerResolver');
  });

  const wireUsers = ({ byId = {}, all = [] }) => {
    mockCollection.mockImplementation(() => ({
      doc: (id) => ({ get: async () => (byId[id] ? makeDoc(id, byId[id]) : missingDoc) }),
      get: async () => ({ docs: all })
    }));
  };

  test('resolves a user by document id', async () => {
    wireUsers({ byId: { u1: { displayName: 'Brittany C' } } });
    const user = await resolver.resolveUser('u1');
    expect(user.displayName).toBe('Brittany C');
  });

  test('resolves an alternate id from linkedProviders', async () => {
    wireUsers({
      byId: { canonical: { displayName: 'Wesley', linkedProviders: { google: 'google-123' } } },
      all: [makeDoc('canonical', { displayName: 'Wesley', linkedProviders: { google: 'google-123' } })]
    });
    const user = await resolver.resolveUser('google-123');
    expect(user.displayName).toBe('Wesley');
  });

  test('returns null for a deleted account rather than throwing', async () => {
    wireUsers({ byId: {}, all: [] });
    expect(await resolver.resolveUser('ghost')).toBeNull();
  });

  test('ignores empty or non-string ids', async () => {
    wireUsers({ byId: {}, all: [] });
    expect(await resolver.resolveUser(null)).toBeNull();
    expect(await resolver.resolveUser('')).toBeNull();
    expect(await resolver.resolveUser(42)).toBeNull();
  });

  test('attaches ownerDetails to another person\'s circle', async () => {
    wireUsers({ byId: { u1: { displayName: 'Brittany C' } } });
    const circle = await resolver.attachOwnerDetails({ owner: 'u1', name: 'NC Things' });
    expect(circle.ownerDetails.displayName).toBe('Brittany C');
    expect(circle.ownerMissing).toBeUndefined();
  });

  test('skips the lookup for your own circle', async () => {
    wireUsers({ byId: { u1: { displayName: 'Me' } } });
    const circle = await resolver.attachOwnerDetails({ owner: 'u1' }, { isOwner: true });
    expect(circle.ownerDetails).toBeUndefined();
  });

  test('flags an orphaned circle instead of leaving it nameless', async () => {
    wireUsers({ byId: {}, all: [] });
    const circle = await resolver.attachOwnerDetails({ owner: 'deleted-user' });
    expect(circle.ownerDetails).toBeUndefined();
    expect(circle.ownerMissing).toBe(true);
  });

  test('batch form resolves each distinct owner once', async () => {
    let reads = 0;
    mockCollection.mockImplementation(() => ({
      doc: (id) => ({
        get: async () => {
          reads += 1;
          return id === 'u1' ? makeDoc('u1', { displayName: 'Brittany C' }) : missingDoc;
        }
      }),
      get: async () => ({ docs: [] })
    }));

    const circles = [{ owner: 'u1' }, { owner: 'u1' }, { owner: 'u1' }];
    await resolver.attachOwnerDetailsToAll(circles, 'someone-else');
    circles.forEach((c) => expect(c.ownerDetails.displayName).toBe('Brittany C'));
    expect(reads).toBe(1); // cached, not three round trips
  });
});
