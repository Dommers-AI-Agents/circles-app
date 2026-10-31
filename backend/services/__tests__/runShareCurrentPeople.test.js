// A shared run names the runner, watchers and cheerers as they are NOW.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: jest.fn() }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: jest.fn() }));

const runs = require('../runShareService');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeAll(async () => {
  await put('users', 'wes', { displayName: 'Wes Sgroi', profilePicture: 'https://x/wes.jpg' });
  await put('users', 'sal', { displayName: 'Sal Sgroi' });
  await put('sharedRuns', 'r1', {
    ownerId: 'wes', ownerName: 'Wesley', ownerAvatarUrl: null, status: 'finished', unit: 'mi', token: 'runtok_abcdefghijk',
    watcherIds: ['sal', 'gone'], watcherNames: { sal: 'Salvatore', gone: 'Ghost' }, invitedIds: ['sal'],
    cheers: [{ fromId: 'sal', fromName: 'Salvatore', emoji: '🔥', at: '2026-10-06' }, { fromId: 'gone', fromName: 'Ghost', emoji: '👏', at: '2026-10-06' }],
    distanceM: 5000, startedAt: '2026-10-06', createdAt: '2026-10-06', updatedAt: '2026-10-06'
  });
});

test('getRun and listWatching: current runner, watchers and cheers; deleted accounts keep stored names', async () => {
  const { run } = await runs.getRun('r1', 'sal');
  const { runs: [listed] } = await runs.listWatching('sal');
  for (const r of [run, listed]) {
    expect(r).toMatchObject({ ownerName: 'Wes Sgroi', ownerAvatarUrl: 'https://x/wes.jpg' });
    expect(r.watchers).toEqual([{ id: 'sal', name: 'Sal Sgroi' }, { id: 'gone', name: 'Ghost' }]);
    expect(r.cheers.map(c => c.fromName)).toEqual(['Sal Sgroi', 'Ghost']);
  }
  expect(await runs.publicPreview('runtok_abcdefghijk')).toEqual({ ownerName: 'Wes Sgroi', live: false });
  // The pure mapper alone keeps the stored values
  expect(runs.toClientRun('r1', (await mockDb.collection('sharedRuns').doc('r1').get()).data(), 'sal').ownerName).toBe('Wesley');
});
