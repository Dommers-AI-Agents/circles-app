// The Inner Circle list: only connections may be on it, removal is immediate,
// and ending a connection cleans both sides.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const mockConnections = new Map(); // userId -> Set of connected ids
jest.mock('../../utils/networkAccess', () => ({
  getConnectedUserIds: jest.fn(async (id) => mockConnections.get(id) || new Set()),
  getInnerCircleGrantorIds: jest.fn(async () => new Set())
}));

const svc = require('../innerCircleService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const users = () => mockDb.rows(COLLECTIONS.USERS);

beforeEach(() => {
  jest.clearAllMocks();
  users().clear();
  mockConnections.clear();
  users().set('owner', { innerCircle: ['a'] });
  users().set('a', { innerCircle: ['owner'] });
  mockConnections.set('owner', new Set(['a', 'b']));
  mockConnections.set('a', new Set(['owner']));
});

test('getInnerCircle tolerates a missing user and junk entries', async () => {
  expect(await svc.getInnerCircle('nobody')).toEqual([]);
  users().set('junk', { innerCircle: ['x', 7, '', null] });
  expect(await svc.getInnerCircle('junk')).toEqual(['x']);
  users().set('none', {});
  expect(await svc.getInnerCircle('none')).toEqual([]);
});

test('setInnerCircle dedupes, drops the owner, and rejects strangers', async () => {
  expect(await svc.setInnerCircle('owner', ['a', 'b', 'a', 'owner'])).toEqual(['a', 'b']);
  expect(users().get('owner').innerCircle).toEqual(['a', 'b']);
  await expect(svc.setInnerCircle('owner', ['a', 'stranger'])).rejects.toMatchObject({ code: 'INNER_CIRCLE_NOT_CONNECTED' });
  expect(users().get('owner').innerCircle).toEqual(['a', 'b']);
});

test('setInnerCircle caps the list before touching the network', async () => {
  const many = Array.from({ length: svc.MAX_INNER_CIRCLE + 1 }, (_, i) => `u${i}`);
  await expect(svc.setInnerCircle('owner', many)).rejects.toMatchObject({ code: 'INNER_CIRCLE_TOO_LARGE' });
  expect(require('../../utils/networkAccess').getConnectedUserIds).not.toHaveBeenCalled();
});

test('add is idempotent and validated; remove is immediate and needs no connection', async () => {
  expect(await svc.addToInnerCircle('owner', 'a')).toEqual(['a']);
  expect(await svc.addToInnerCircle('owner', 'b')).toEqual(['a', 'b']);
  await expect(svc.addToInnerCircle('owner', 'stranger')).rejects.toMatchObject({ code: 'INNER_CIRCLE_NOT_CONNECTED' });
  mockConnections.set('owner', new Set()); // they all disconnected
  expect(await svc.removeFromInnerCircle('owner', 'a')).toEqual(['b']);
  expect(await svc.removeFromInnerCircle('owner', 'never-there')).toEqual(['b']);
  expect(users().get('owner').innerCircle).toEqual(['b']);
});

test('revokeMutualGrants cleans both lists and is safe when neither mentions the other', async () => {
  await svc.revokeMutualGrants('owner', 'a');
  expect(users().get('owner').innerCircle).toEqual([]);
  expect(users().get('a').innerCircle).toEqual([]);
  await expect(svc.revokeMutualGrants('owner', 'a')).resolves.toBeUndefined();
});

describe('named lists', () => {
  test('a legacy list is presented as one named list and can be added to', async () => {
    expect(await svc.getInnerCircleLists('owner')).toEqual([
      { id: 'default', name: 'Inner Circle', userIds: ['a'] }
    ]);
    const lists = await svc.createInnerCircleList('owner', { name: '  Gym crew ', userIds: ['b'] });
    expect(lists.map((l) => l.name)).toEqual(['Inner Circle', 'Gym crew']);
    // The flat field is the index the reverse lookup reads: everyone, once.
    expect(users().get('owner').innerCircle.sort()).toEqual(['a', 'b']);
  });

  test('a list can be renamed and re-peopled, and only connections may be on it', async () => {
    const [created] = (await svc.createInnerCircleList('owner', { name: 'Gym', userIds: ['b'] })).slice(-1);
    const lists = await svc.updateInnerCircleList('owner', created.id, { name: 'Gym crew', userIds: ['a', 'b'] });
    expect(lists.find((l) => l.id === created.id)).toMatchObject({ name: 'Gym crew', userIds: ['a', 'b'] });
    await expect(svc.updateInnerCircleList('owner', created.id, { userIds: ['stranger'] }))
      .rejects.toMatchObject({ code: 'INNER_CIRCLE_NOT_CONNECTED' });
    await expect(svc.updateInnerCircleList('owner', 'nope', { name: 'x' }))
      .rejects.toMatchObject({ code: 'INNER_CIRCLE_NO_LIST' });
    // Renaming alone leaves the members be.
    const renamed = await svc.updateInnerCircleList('owner', created.id, { name: 'Gym' });
    expect(renamed.find((l) => l.id === created.id).userIds).toEqual(['a', 'b']);
  });

  test('deleting a list takes its people out of the index unless another list has them', async () => {
    const created = (await svc.createInnerCircleList('owner', { name: 'Gym', userIds: ['a', 'b'] })).slice(-1)[0];
    expect(users().get('owner').innerCircle.sort()).toEqual(['a', 'b']);
    await svc.deleteInnerCircleList('owner', created.id);
    // 'a' is still on the default list; 'b' was only on the deleted one.
    expect(users().get('owner').innerCircle).toEqual(['a']);
    await expect(svc.deleteInnerCircleList('owner', created.id)).rejects.toMatchObject({ code: 'INNER_CIRCLE_NO_LIST' });
  });

  test('removing someone takes them off EVERY list, because revocation is total', async () => {
    await svc.createInnerCircleList('owner', { name: 'Gym', userIds: ['a', 'b'] });
    await svc.removeFromInnerCircle('owner', 'a');
    const lists = await svc.getInnerCircleLists('owner');
    expect(lists.flatMap((l) => l.userIds)).toEqual(['b']);
    expect(users().get('owner').innerCircle).toEqual(['b']);
  });

  test('the number of lists is capped', async () => {
    for (let i = 0; i < svc.MAX_LISTS - 1; i++) {
      await svc.createInnerCircleList('owner', { name: `L${i}`, userIds: [] });
    }
    await expect(svc.createInnerCircleList('owner', { name: 'one too many' }))
      .rejects.toMatchObject({ code: 'INNER_CIRCLE_TOO_MANY_LISTS' });
  });
});

test('validateGuestList applies the same connected-only rule to sharedWith', async () => {
  expect(await svc.validateGuestList('owner', [])).toEqual([]);
  expect(await svc.validateGuestList('owner', ['b', 'b', 'owner'])).toEqual(['b']);
  await expect(svc.validateGuestList('owner', ['b', 'zed'])).rejects.toMatchObject({ code: 'SHARED_WITH_NOT_CONNECTED' });
});
