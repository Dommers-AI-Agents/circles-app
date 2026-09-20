// The daily quote: delivered at the hour the user picked, in their own
// timezone, once a day even if the scheduler runs twice, in the topics they
// chose, and to their inbox only when they asked for it.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn(async () => ({ success: true })) }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn(async () => ({ messageId: 'm1' })) }));

const notificationService = require('../notificationService');
const emailService = require('../emailService');
const quotes = require('../quotesService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const ME = 'user_1';
const users = () => mockDb.rows(COLLECTIONS.USERS);
const catalog = () => mockDb.rows(COLLECTIONS.QUOTES);
const sends = () => mockDb.rows(COLLECTIONS.QUOTE_SENDS);

// 12:35 UTC = 08:35 New York, 05:35 Los Angeles
const T_0835_NY = new Date('2026-09-19T12:35:00Z');

const seedUser = (extra = {}) => users().set(ME, {
  displayName: 'Wes Sgroi',
  email: 'wes@example.com',
  notificationPreferences: { timezone: 'America/New_York' },
  quotePrefs: { enabled: true, categories: ['motivation'], time: '08:00', email: false },
  ...extra
});

const seedQuotes = () => {
  catalog().set('q1', { text: 'Start where you are.', author: 'Arthur Ashe', categories: ['motivation'], enabled: true });
  catalog().set('q2', { text: 'Breathe.', author: null, categories: ['calm'], enabled: true });
  catalog().set('q3', { text: 'Keep going.', author: null, categories: ['motivation', 'resilience'], enabled: true });
};

beforeEach(() => {
  users().clear(); catalog().clear(); sends().clear();
  notificationService.sendToUser.mockClear();
  emailService.sendEmail.mockClear();
  emailService.sendEmail.mockImplementation(async () => ({ messageId: 'm1' }));
});

describe('settings', () => {
  test('defaults are off, and the categories come back for the picker', async () => {
    users().set(ME, { displayName: 'Wes' });
    const { prefs, categories } = await quotes.getSettings(ME);
    expect(prefs).toMatchObject({ enabled: false, time: '08:00', email: false });
    expect(categories.map((c) => c.id)).toContain('motivation');
  });

  test('the time must be a real time, and the topics must be real topics', async () => {
    seedUser();
    await expect(quotes.updateSettings(ME, { time: 'morning' })).rejects.toMatchObject({ code: 'bad_time' });
    await expect(quotes.updateSettings(ME, { categories: 'motivation' })).rejects.toMatchObject({ code: 'bad_categories' });

    const { prefs } = await quotes.updateSettings(ME, { categories: ['calm', 'nonsense', 'calm'], time: '21:30', email: true });
    expect(prefs.categories).toEqual(['calm']);
    expect(prefs).toMatchObject({ time: '21:30', email: true });
  });

  test('clearing every topic means surprise me, not silence', async () => {
    seedUser();
    const { prefs } = await quotes.updateSettings(ME, { categories: [] });
    expect(prefs.categories.length).toBeGreaterThan(1);
  });
});

describe('delivery', () => {
  test('goes out at the hour the user picked, in THEIR timezone', async () => {
    seedUser(); seedQuotes();
    // 08:35 in New York — inside their 08:00 hour.
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(1);
    const [, payload] = notificationService.sendToUser.mock.calls[0];
    expect(payload).toMatchObject({ type: 'daily_quote', title: 'A line for you' });
    // Which of the motivation quotes is chosen is deliberately not fixed; that
    // it came from the chosen topic, and reads with its author, is.
    expect(['Start where you are. — Arthur Ashe', 'Keep going.']).toContain(payload.body);
  });

  test('the same instant is the wrong hour for someone three zones west', async () => {
    seedUser({ notificationPreferences: { timezone: 'America/Los_Angeles' } });
    seedQuotes();
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(0);   // 05:35 there
    const laMorning = new Date('2026-09-19T15:20:00Z');               // 08:20 there
    expect((await quotes.runDue({ now: laMorning })).sent).toBe(1);
  });

  test('a retried run does not send a second quote', async () => {
    seedUser(); seedQuotes();
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(1);
    const again = await quotes.runDue({ now: T_0835_NY });
    expect(again.sent).toBe(0);
    expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
  });

  test('several times a day: each slot sends once, and the widget sees the latest', async () => {
    seedUser({ quotePrefs: { enabled: true, categories: ['motivation'], times: ['08:00', '13:00', '18:30'], email: false } });
    seedQuotes();
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(1);
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(0);                       // same slot, retried
    expect((await quotes.runDue({ now: new Date('2026-09-19T16:00:00Z') })).sent).toBe(0); // 12:00 NY, no slot
    expect((await quotes.runDue({ now: new Date('2026-09-19T17:10:00Z') })).sent).toBe(1); // 13:10 NY
    expect((await quotes.runDue({ now: new Date('2026-09-19T22:45:00Z') })).sent).toBe(1); // 18:45 NY
    expect([...sends().keys()].sort()).toEqual([`${ME}_2026-09-19_0800`, `${ME}_2026-09-19_1300`, `${ME}_2026-09-19_1830`]);
    const { today, prefs } = await quotes.getSettings(ME, { now: new Date('2026-09-19T23:00:00Z') });
    expect(today.slot).toBe('18:30');
    expect(prefs.times).toEqual(['08:00', '13:00', '18:30']);
    expect(prefs.time).toBe('08:00');
  });

  test('times are validated, capped at six, and `time` from an old client still works', async () => {
    seedUser();
    await expect(quotes.updateSettings(ME, { times: ['8am'] })).rejects.toMatchObject({ code: 'bad_time' });
    await expect(quotes.updateSettings(ME, { times: [] })).rejects.toMatchObject({ code: 'bad_time' });
    await expect(quotes.updateSettings(ME, { times: ['01:00', '02:00', '03:00', '04:00', '05:00', '06:00', '07:00'] })).rejects.toMatchObject({ code: 'bad_time' });
    expect((await quotes.updateSettings(ME, { times: ['18:00', '07:30', '18:00'] })).prefs).toMatchObject({ times: ['07:30', '18:00'], time: '07:30' });
    expect((await quotes.updateSettings(ME, { time: '09:15' })).prefs).toMatchObject({ times: ['09:15'], time: '09:15' });
  });

  test('turned off means nothing goes out', async () => {
    seedUser({ quotePrefs: { enabled: false, categories: ['motivation'], time: '08:00', email: false } });
    seedQuotes();
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(0);
    expect(notificationService.sendToUser).not.toHaveBeenCalled();
  });

  test('only the chosen topics, unless that would mean sending nothing', async () => {
    seedUser({ quotePrefs: { enabled: true, categories: ['calm'], time: '08:00', email: false } });
    seedQuotes();
    await quotes.runDue({ now: T_0835_NY });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(ME, expect.objectContaining({ body: 'Breathe.' }));

    // A topic with nothing in it falls back to the whole catalog rather than
    // leaving the user with no quote at all.
    sends().clear();
    users().set(ME, { ...users().get(ME), quotePrefs: { enabled: true, categories: ['adventure'], time: '08:00', email: false } });
    notificationService.sendToUser.mockClear();
    expect((await quotes.runDue({ now: T_0835_NY })).sent).toBe(1);
  });

  test('email only when asked for, and a failed email does not lose the day', async () => {
    seedUser({ quotePrefs: { enabled: true, categories: ['motivation'], time: '08:00', email: false } });
    seedQuotes();
    await quotes.runDue({ now: T_0835_NY });
    expect(emailService.sendEmail).not.toHaveBeenCalled();

    sends().clear();
    users().set(ME, { ...users().get(ME), quotePrefs: { enabled: true, categories: ['motivation'], time: '08:00', email: true } });
    const result = await quotes.runDue({ now: T_0835_NY });
    expect(result.emailed).toBe(1);
    expect(emailService.sendEmail).toHaveBeenCalledWith(expect.objectContaining({ to: 'wes@example.com' }));

    // The push already landed; the email failing must not read as a failed day.
    sends().clear();
    emailService.sendEmail.mockImplementation(async () => { throw new Error('smtp down'); });
    const after = await quotes.runDue({ now: T_0835_NY });
    expect(after.sent).toBe(1);
    expect(after.emailed).toBe(0);
  });

  test('quotes do not repeat while there are unseen ones', async () => {
    seedUser({ quotePrefs: { enabled: true, categories: ['motivation', 'calm', 'resilience'], time: '08:00', email: false } });
    seedQuotes();
    const seen = new Set();
    for (let day = 0; day < 3; day++) {
      sends().clear();
      await quotes.runDue({ now: T_0835_NY });
      const last = users().get(ME).quoteRecentIds.slice(-1)[0];
      seen.add(last);
    }
    expect(seen.size).toBe(3);
  });

  test('an empty catalog is a skip, not a crash', async () => {
    seedUser();
    const result = await quotes.runDue({ now: T_0835_NY });
    expect(result.sent).toBe(0);
    expect(notificationService.sendToUser).not.toHaveBeenCalled();
  });

  test("today's quote comes back for the widget once it has gone out", async () => {
    seedUser(); seedQuotes();
    expect((await quotes.getSettings(ME)).today).toBeNull();
    await quotes.runDue({ now: T_0835_NY });
    const { today } = await quotes.getSettings(ME, { now: T_0835_NY });
    expect(['Start where you are.', 'Keep going.']).toContain(today.text);
    expect(today.sentAt).toBeTruthy();
  });
});

describe('read bounds (B1b)', () => {
  test('one run reads the catalog once, however many people are due', async () => {
    seedUser(); seedQuotes();
    users().set('other', { ...users().get(ME), id: 'other', displayName: 'Other' });
    const spy = jest.spyOn(quotes, 'loadEnabledQuotes');
    const result = await quotes.runDue({ now: new Date('2026-09-19T12:35:00Z'), force: true });
    expect(result.due).toBe(2);
    expect(spy).toHaveBeenCalledTimes(1);
    spy.mockRestore();
  });
});
