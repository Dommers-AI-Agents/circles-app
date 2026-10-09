jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: {} }));
jest.mock('../notificationService', () => ({}));
const { lastSeen } = require('../scheduledNotifications');

// "We miss you" goes by when they last used the app, not their last sign-in
// (2026-10-09: daily users who signed in once got it in week 2).
test('the latest of lastActive / lastAppOpenAt / lastLogin wins', () => {
  const user = { lastLogin: '2026-10-01T10:00:00Z', lastActive: '2026-10-08T09:00:00Z', lastAppOpenAt: '2026-10-07T09:00:00Z' };
  expect(lastSeen(user).toISOString()).toBe('2026-10-08T09:00:00.000Z');
  expect(lastSeen({ lastLogin: '2026-10-01T10:00:00Z' }).toISOString()).toBe('2026-10-01T10:00:00.000Z');
  expect(lastSeen({ lastActive: { toDate: () => new Date('2026-10-05T00:00:00Z') } }).toISOString()).toBe('2026-10-05T00:00:00.000Z');
  expect(lastSeen({})).toBeNull();
  expect(lastSeen({ lastLogin: 'not a date' })).toBeNull();
});
