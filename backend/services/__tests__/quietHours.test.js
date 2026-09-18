// Quiet hours run on the USER'S clock, not the server's.
//
// Cloud Run is UTC, so the old `new Date().getHours()` applied a user's chosen
// window at their UTC offset: an Eastern user asking for 22:00-08:00 was
// silenced 18:00-04:00 their time. These pin the window to the timezone on the
// user's preferences.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) }),
  getMessaging: () => ({}),
  FieldValue: {}
}));
jest.mock('../emailService', () => ({}));
jest.mock('../sseService', () => ({ notifyUser: jest.fn() }));

const notificationService = require('../notificationService');
const { localClock } = require('../../utils/localClock');

const at = (iso) => {
  const real = Date;
  global.Date = class extends real {
    constructor(...args) { return args.length ? new real(...args) : new real(iso); }
    static now() { return new real(iso).getTime(); }
  };
  return () => { global.Date = real; };
};

const prefs = (extra = {}) => ({
  quietHoursEnabled: true,
  quietHoursStart: '22:00',
  quietHoursEnd: '08:00',
  timezone: 'America/New_York',
  ...extra
});

describe('quiet hours', () => {
  test('an evening push goes through, even though it is already tomorrow in UTC', () => {
    // 01:00 UTC = 21:00 in New York — before the window opens.
    const restore = at('2026-09-18T01:00:00Z');
    expect(notificationService.isInQuietHours(prefs())).toBe(false);
    restore();
  });

  test('the window is silent in the user\'s own evening and night', () => {
    for (const iso of ['2026-09-18T02:30:00Z',   // 22:30 New York
                       '2026-09-18T06:00:00Z',   // 02:00 New York
                       '2026-09-18T11:30:00Z']) { // 07:30 New York
      const restore = at(iso);
      expect(notificationService.isInQuietHours(prefs())).toBe(true);
      restore();
    }
  });

  test('the old server-clock behaviour is gone: 18:00-04:00 local is NOT silent', () => {
    // 22:00 UTC is 18:00 in New York. Under the server clock this was inside
    // the window and every notification was dropped through the user's evening.
    const restore = at('2026-09-17T22:00:00Z');
    expect(notificationService.isInQuietHours(prefs())).toBe(false);
    restore();
  });

  test('a west-coast user gets their own window, not the east coast\'s', () => {
    // 05:30 UTC = 22:30 Los Angeles, 01:30 New York.
    const restore = at('2026-09-18T05:30:00Z');
    expect(notificationService.isInQuietHours(prefs({ timezone: 'America/Los_Angeles' }))).toBe(true);
    restore();
  });

  test('a daytime window that does not cross midnight still works', () => {
    const day = prefs({ quietHoursStart: '09:00', quietHoursEnd: '17:00' });
    let restore = at('2026-09-18T16:00:00Z');        // 12:00 New York
    expect(notificationService.isInQuietHours(day)).toBe(true);
    restore();
    restore = at('2026-09-18T22:00:00Z');            // 18:00 New York
    expect(notificationService.isInQuietHours(day)).toBe(false);
    restore();
  });

  test('disabled means never silent; a missing or bad timezone falls back to Eastern', () => {
    const restore = at('2026-09-18T02:30:00Z');      // 22:30 New York
    expect(notificationService.isInQuietHours(prefs({ quietHoursEnabled: false }))).toBe(false);
    expect(notificationService.isInQuietHours(prefs({ timezone: undefined }))).toBe(true);
    expect(notificationService.isInQuietHours(prefs({ timezone: 'Not/AZone' }))).toBe(true);
    restore();
  });

  test('localClock reports the user\'s wall clock and minutes since midnight', () => {
    const now = new Date('2026-09-18T02:30:00Z');
    expect(localClock('America/New_York', now)).toMatchObject({ hour: 22, minute: 30, minutes: 1350 });
    expect(localClock('America/Los_Angeles', now)).toMatchObject({ hour: 19, minute: 30 });
  });
});
