// Bell rows show the sender as they are NOW (name/photo from their users
// record); the title/body text stays as written.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const controller = require('../notificationController');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

test('fromUser and sender names/photos are current; text and deleted senders stay as stored', async () => {
  await put('users', 'u1', { displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
  await put('notifications', 'n1', { userId: 'me', createdAt: '2026-10-03', type: 'activity_reaction', title: 'New Reaction',
    body: 'Salvatore reacted', data: { fromUserId: 'u1', fromUserName: 'Salvatore', fromUserPhoto: 'https://x/old.jpg' } });
  await put('notifications', 'n2', { userId: 'me', createdAt: '2026-10-02', type: 'new_message', title: '💬 Salvatore',
    body: 'hey', data: { senderId: 'u1', senderName: 'Salvatore', senderPhoto: null } });
  await put('notifications', 'n3', { userId: 'me', createdAt: '2026-10-01', type: 'follow', title: 'T', body: 'B',
    data: { fromUserId: 'gone', fromUserName: 'Old Name' } });
  await put('notifications', 'n4', { userId: 'me', createdAt: '2026-09-30', type: 'water', title: 'T', body: 'B', data: { fromUserId: 'u1' } });

  let body;
  const res = { status() { return this; }, json(b) { body = b; return this; } };
  await controller.getNotifications({ user: { uid: 'me' }, query: {} }, res, (e) => { throw e; });
  const byId = Object.fromEntries(body.notifications.map((n) => [n.id, n]));
  expect(byId.n1).toMatchObject({ body: 'Salvatore reacted', data: { fromUserName: 'Sal Sgroi', fromUserPhoto: 'https://x/new.jpg' } });
  expect(byId.n2).toMatchObject({ title: '💬 Salvatore', data: { senderName: 'Sal Sgroi', senderPhoto: 'https://x/new.jpg' } });
  expect(byId.n3.data).toEqual({ fromUserId: 'gone', fromUserName: 'Old Name' });
  expect(byId.n4.data).toEqual({ fromUserId: 'u1' });
});
