// Viral-growth review 2026-10-01: the hourly tips and weekly-summary jobs now
// skip reading users in hours when no timezone can match. The skip must never
// hide a real match, so this walks every hour of a week across real zones
// (including the odd ones: +5:45, +13, +14, −10, half-hour offsets) and
// checks the pre-check is true whenever any user would actually match.
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) }),
  FieldValue: {}
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn() }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn(), isConfigured: true }));
jest.mock('../sseService', () => ({ notifyUser: jest.fn() }));

const dailySummary = require('../dailySummaryService');
const tips = require('../tipsService');

const ZONES = [
  'America/New_York', 'America/Los_Angeles', 'Pacific/Honolulu', 'Pacific/Pago_Pago',
  'Pacific/Kiritimati', 'Pacific/Tongatapu', 'Pacific/Chatham', 'Asia/Kathmandu',
  'Asia/Kolkata', 'Australia/Adelaide', 'Europe/London', 'America/St_Johns', 'Asia/Tokyo', 'not/a-zone'
];
const START = Date.parse('2026-10-04T00:00:00Z'); // a Sunday

describe('no-zone pre-checks never hide a match', () => {
  test('weekly summary', () => {
    for (let h = 0; h < 24 * 8; h++) {
      const now = new Date(START + h * 3600 * 1000);
      for (const timezone of ZONES) {
        for (let hour = 0; hour < 24; hour++) {
          const user = { notificationPreferences: { timezone, summaryTime: `${hour}:00` } };
          if (dailySummary.isUsersSummaryHour(user, now)) {
            expect(dailySummary.anyZoneOnSummaryDay(now)).toBe(true);
          }
        }
      }
    }
  });

  test('tips', () => {
    const RealDate = Date;
    let skippedHours = 0;
    let matchedHours = 0;
    for (let h = 0; h < 24 * 8; h++) {
      const now = new RealDate(START + h * 3600 * 1000);
      // isUsersTipTime reads the clock itself; pin it for this hour.
      global.Date = class extends RealDate { constructor(...a) { super(...(a.length ? a : [now.getTime()])); } };
      try {
        const anyMatch = ZONES.some((timezone) => tips.isUsersTipTime({ notificationPreferences: { timezone } }));
        if (anyMatch) { matchedHours += 1; expect(tips.anyZoneAtTipTime(now)).toBe(true); }
        if (!tips.anyZoneAtTipTime(now)) skippedHours += 1;
      } finally {
        global.Date = RealDate;
      }
    }
    // And it actually saves work: most hours of the week read nothing.
    expect(matchedHours).toBeGreaterThan(0);
    expect(skippedHours).toBeGreaterThan(24 * 8 / 2);
  });
});
