// The profile bell is one person's choice about the other, and a burst of
// photos is one push (Wes, 2026-10-16).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { wantsActivityPush, claimPushSlot, PHOTO_PUSH_WINDOW_MS } = require('../activityPushPrefs');

describe('activity push preferences', () => {
  test('only the member who turned on the bell is notified about the other', () => {
    const connection = { userId: 'wes', connectedUserId: 'sal', activityNotifyUserIds: ['wes'] };
    expect(wantsActivityPush(connection, 'wes')).toBe(true);   // Wes asked to hear about Sal
    expect(wantsActivityPush(connection, 'sal')).toBe(false);  // Sal never asked to hear about Wes
  });

  test('the old shared flag sends nothing: it never said whose choice it was', () => {
    expect(wantsActivityPush({ userId: 'wes', connectedUserId: 'sal', activityNotificationsEnabled: true }, 'sal')).toBe(false);
    expect(wantsActivityPush(null, 'sal')).toBe(false);
    expect(wantsActivityPush({ activityNotifyUserIds: ['sal'] }, null)).toBe(false);
  });

  test('one push per actor, place and window; a new window or place pushes again', async () => {
    const now = Date.UTC(2026, 9, 16, 19, 43);
    expect(await claimPushSlot('photo_uploaded', 'wes', 'pasta', now)).toBe(true);
    expect(await claimPushSlot('photo_uploaded', 'wes', 'pasta', now + 2000)).toBe(false);
    expect(await claimPushSlot('photo_uploaded', 'wes', 'pasta', now + 4000)).toBe(false);
    expect(await claimPushSlot('photo_uploaded', 'wes', 'other-place', now)).toBe(true);
    expect(await claimPushSlot('photo_uploaded', 'wes', 'pasta', now + PHOTO_PUSH_WINDOW_MS)).toBe(true);
  });
});
