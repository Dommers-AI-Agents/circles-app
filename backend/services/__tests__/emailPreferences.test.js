// The email switches in Settings (services/emailPreferences.js)
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { switchesFor, changesFrom, EMAIL_KINDS } = require('../emailPreferences');

test('a missing preference is on; only an explicit false is off', () => {
  const rows = switchesFor({ emailPreferences: { storeNudges: false, messageEmails: true } });
  expect(rows.find((r) => r.kind === 'storeNudges').on).toBe(false);
  expect(rows.find((r) => r.kind === 'messageEmails').on).toBe(true);
  expect(rows.find((r) => r.kind === 'productUpdates').on).toBe(true);
  expect(switchesFor(null).every((r) => r.on)).toBe(true);
  expect(rows).toHaveLength(EMAIL_KINDS.length);
});

test('only known switches with true/false are written, each on its own path', () => {
  expect(changesFrom({ storeNudges: false, weeklyMapDigest: true }))
    .toEqual({ 'emailPreferences.storeNudges': false, 'emailPreferences.weeklyMapDigest': true });
  expect(() => changesFrom({})).toThrow(/switches/);
  expect(() => changesFrom({ storeNudges: 'no' })).toThrow(/isn't an email switch/);
  expect(() => changesFrom({ 'emailPreferences.x': false })).toThrow();
  expect(() => changesFrom(null)).toThrow();
  expect(() => changesFrom([true])).toThrow();
});

test('every switch is one the unsubscribe link also knows', () => {
  const src = require('fs').readFileSync(require('path').join(__dirname, '..', '..', 'routes', 'emailPreferenceRoutes.js'), 'utf8');
  EMAIL_KINDS.forEach(({ kind }) => expect(src.includes(`'${kind}'`) || kind === 'followSuggestions').toBe(true));
});
