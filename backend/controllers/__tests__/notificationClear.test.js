// Clear All catches every active row — including ones from before the
// `archived` field existed, which used to come straight back.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

// The fake has no batches; apply each write when committed
mockDb.batch = () => {
  const ops = [];
  return {
    update: (ref, data) => ops.push(() => ref.update(data)),
    delete: (ref) => ops.push(() => ref.delete()),
    commit: async () => { for (const op of ops) await op(); }
  };
};

const controller = require('../notificationController');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};

test('archive-all archives (and reads) legacy rows with no archived field', async () => {
  const add = (id, extra) => mockDb.collection('notifications').doc(id).set({ userId: 'wes', type: 'activity_reaction', title: 'T', body: 'B', read: false, ...extra });
  await add('legacy', {});                         // no archived field at all
  await add('active', { archived: false });
  await add('done', { archived: true, read: true });
  await add('other', { archived: false, userId: 'someone' });

  const out = res();
  await controller.archiveAllNotifications({ user: { uid: 'wes' } }, out, (e) => { throw e; });
  const row = (id) => mockDb.rows('notifications').get(id);
  expect(row('legacy')).toMatchObject({ archived: true, read: true });
  expect(row('active')).toMatchObject({ archived: true, read: true });
  expect(row('other').archived).toBe(false);
  expect(out.json.mock.calls[0][0].message).toBe('Archived 2 notifications');
});
