// A push that should be findable later leaves exactly one Notifications row.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({ sendEachForMulticast: jest.fn(async () => ({ successCount: 0, responses: [] })) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../emailService', () => ({}));
jest.mock('../emailFallback', () => ({ maybeEmail: jest.fn() }));
jest.mock('../sseService', () => ({ notifyUser: jest.fn() }));

const notifications = require('../notificationService');
const { validateNotification, createNotification } = require('../../models/FirestoreModels');

const rows = () => [...mockDb.rows('notifications').values()];

beforeEach(async () => {
  mockDb.rows('notifications').clear();
  mockDb.rows('users').clear();
  // No phone: the push can't go, the row still must
  await mockDb.collection('users').doc('amanda').set({ displayName: 'Amanda', deviceTokens: [] });
});

test('newer push types are storable (the old hard-coded list dropped them)', () => {
  expect(validateNotification(createNotification({ userId: 'u', type: 'care_watcher_invite', title: 'T', body: 'B' }))).toEqual([]);
  expect(validateNotification(createNotification({ userId: 'u', type: 'not_a_type', title: 'T', body: 'B' }))).not.toEqual([]);
});

test('a How Are You? invitation leaves a row even when the push can\'t be delivered', async () => {
  await notifications.sendToUser('amanda', { type: 'care_watcher_invite', title: 'Wes invited you', body: 'Check in on Sal', data: { planId: 'p1' } });
  expect(rows()).toHaveLength(1);
  expect(rows()[0]).toMatchObject({ userId: 'amanda', type: 'care_watcher_invite', read: false, archived: false });
});

test('sendToUserWithRecord writes one row, not two', async () => {
  await notifications.sendToUserWithRecord('amanda', { type: 'care_invite', title: 'T', body: 'B' });
  expect(rows()).toHaveLength(1);
});

test('reminders stay push-only', async () => {
  await notifications.sendToUser('amanda', { type: 'engagement_reminder', title: 'T', body: 'B' });
  await notifications.sendToUser('amanda', { type: 'care_ask', title: 'How are you?', body: 'B' });
  expect(rows()).toHaveLength(0);
});
