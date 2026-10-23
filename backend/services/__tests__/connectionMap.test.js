// A merge tombstone is not a connection. Serving one put a status the iOS
// enum had never seen into a strictly decoded array and blanked every
// connections list the app has (Inner Circle picker, tagging, My Network).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const { buildConnectionMap, isLiveConnection, onePerPerson } = require('../connectionMap');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const ME = 'me';
const conns = () => mockDb.rows(COLLECTIONS.CONNECTIONS);

beforeEach(() => { conns().clear(); });

describe('isLiveConnection', () => {
  it('accepts the statuses a client knows', () => {
    for (const status of ['pending', 'accepted', 'blocked', 'following']) {
      expect(isLiveConnection({ status })).toBe(true);
    }
  });

  it('rejects merge tombstones and anything else unfamiliar', () => {
    expect(isLiveConnection({ status: 'merged', deletedAt: '2026-09-22T13:39:02Z', deletedViaMerge: true })).toBe(false);
    // Any one of the tombstone marks is enough — the merge writes all three,
    // but a reader must not depend on that.
    expect(isLiveConnection({ status: 'accepted', deletedAt: '2026-09-22T13:39:02Z' })).toBe(false);
    expect(isLiveConnection({ status: 'accepted', deletedViaMerge: true })).toBe(false);
    expect(isLiveConnection({ status: 'something_new' })).toBe(false);
    expect(isLiveConnection(null)).toBe(false);
  });
});

describe('buildConnectionMap', () => {
  it('leaves a folded (merged) row out, in either direction', async () => {
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('live').set({ userId: ME, connectedUserId: 'friend', status: 'accepted' });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('dead-out').set({ userId: ME, connectedUserId: 'ghost', status: 'merged', deletedAt: 'x', deletedViaMerge: true });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('dead-in').set({ userId: 'ghost2', connectedUserId: ME, status: 'merged', deletedAt: 'x', deletedViaMerge: true });
    const map = await buildConnectionMap(ME);
    expect([...map.keys()]).toEqual(['friend']);
    expect(map.get('friend').status).toBe('accepted');
  });
});

// Wes saw Dan Wickner twice in his connections: their pair has two accepted
// docs, one each way, left by a 2025 merge script.
describe('onePerPerson', () => {
  const snap = (id, data) => ({ id, data: () => data });

  it('keeps one row for a pair stored both ways, preferring the caller\'s own', () => {
    const mine = snap('mine', { userId: ME, connectedUserId: 'dan', status: 'accepted', createdAt: '2025-07-31T01:18:52Z' });
    const theirs = snap('theirs', { userId: 'dan', connectedUserId: ME, status: 'accepted', createdAt: { _seconds: 1753958324 } });
    const other = snap('other', { userId: ME, connectedUserId: 'amy', status: 'accepted' });
    expect(onePerPerson([theirs, other, mine], ME).map((d) => d.id)).toEqual(['other', 'mine']);
  });

  it('prefers an accepted row over a pending one, whoever owns it', () => {
    const pending = snap('p', { userId: ME, connectedUserId: 'dan', status: 'pending' });
    const accepted = snap('a', { userId: 'dan', connectedUserId: ME, status: 'accepted' });
    expect(onePerPerson([pending, accepted], ME).map((d) => d.id)).toEqual(['a']);
  });

  it('on a full tie keeps the older row', () => {
    const newer = snap('new', { userId: ME, connectedUserId: 'dan', status: 'accepted', createdAt: '2025-08-01T00:00:00Z' });
    const older = snap('old', { userId: ME, connectedUserId: 'dan', status: 'accepted', createdAt: '2025-06-01T00:00:00Z' });
    expect(onePerPerson([newer, older], ME).map((d) => d.id)).toEqual(['old']);
  });
});
