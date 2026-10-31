// The chat list names the last sender as they are NOW, not as they were
// when the message was sent.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, getMessaging: () => ({}) }));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));

const { getConversations } = require('../messagingController');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

test('lastMessageSenderName is current; a deleted sender keeps the stored name', async () => {
  await put('users', 'britt', { displayName: 'Brittany S' });
  await put('conversations', 'g1', { type: 'group', participants: ['wes', 'britt'], lastMessage: 'hi',
    lastMessageTime: '2026-10-02', lastMessageSenderId: 'britt', lastMessageSenderName: 'Britt' });
  await put('conversations', 'g2', { type: 'group', participants: ['wes', 'gone'], lastMessage: 'yo',
    lastMessageTime: '2026-10-01', lastMessageSenderId: 'gone', lastMessageSenderName: 'Old Name' });
  await put('conversations', 'd1', { type: 'direct', participants: ['wes', 'britt'], lastMessage: 'x',
    lastMessageTime: '2026-09-30', lastMessageSenderId: 'britt' });
  let body;
  const res = { status() { return this; }, json(b) { body = b; return this; } };
  await getConversations({ user: { uid: 'wes' } }, res);
  const byId = Object.fromEntries(body.conversations.map((c) => [c.id, c]));
  expect(byId.g1.lastMessageSenderName).toBe('Brittany S');
  expect(byId.g2.lastMessageSenderName).toBe('Old Name');
  expect('lastMessageSenderName' in byId.d1).toBe(false);
  expect(byId.d1.participantDetails[0].displayName).toBe('Brittany S');
});
