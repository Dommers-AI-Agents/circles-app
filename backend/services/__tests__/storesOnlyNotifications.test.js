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

const { isStoresOnly, reachesStoresOnly, TYPES } = require('../notificationTypes');
const svc = require('../notificationService');

describe('Stores I follow only', () => {
  test('only notificationPreferences.mode storesOnly turns it on', () => {
    expect(isStoresOnly({ mode: 'storesOnly' })).toBe(true);
    expect(isStoresOnly({ mode: 'all' })).toBe(false);
    expect(isStoresOnly({})).toBe(false);
    expect(isStoresOnly(undefined)).toBe(false);
  });

  test('their stores and things they are waiting on still arrive', () => {
    ['store_alert', 'store_nudge', 'waitlist_ready', 'waitlist_update', 'order_update', 'receipt_result']
      .forEach((type) => expect(reachesStoresOnly(type)).toBe(true));
  });

  test('friends, tips and reminders wait until they choose more', () => {
    ['new_message', 'connection_request', 'new_suggestion', 'new_follower', 'place_like', 'did_you_know',
      'daily_quote', 'engagement_reminder', 'weekly_summary', 'social_activity', 'event_invite']
      .forEach((type) => expect(reachesStoresOnly(type)).toBe(false));
  });

  test('the service drops the rest and keeps every other switch', () => {
    {
      const prefs = { mode: 'storesOnly' };
      expect(svc.isNotificationEnabled('store_alert', prefs)).toBe(true);
      expect(svc.isNotificationEnabled('new_suggestion', prefs)).toBe(false);
      expect(svc.isNotificationEnabled('new_suggestion', { mode: 'all' })).toBe(true);
      expect(svc.isNotificationEnabled('store_alert', { mode: 'storesOnly', storeAlerts: false })).toBe(false);
    }
  });

  test('every type in the table is classified without throwing', () => {
    Object.keys(TYPES).forEach((type) => expect(typeof reachesStoresOnly(type)).toBe('boolean'));
  });
});
