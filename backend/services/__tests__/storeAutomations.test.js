// Store automations: settings checks, the daily plan's rules, the pending
// bonus, and a run that never sends twice.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: MockFieldValue,
  admin: { firestore: { FieldValue: MockFieldValue } }
}));
const mockPush = jest.fn(async () => ({ success: true }));
jest.mock('../notificationService', () => ({ sendToUser: (...args) => mockPush(...args) }));
const mockEmail = jest.fn(async () => ({}));
jest.mock('../emailService', () => ({ sendEmail: (...args) => mockEmail(...args) }));
jest.mock('../followSuggestionEmailService', () => ({ unsubscribeUrl: (uid, kind) => `https://x/unsub?uid=${uid}&kind=${kind}` }));
jest.mock('../ownerSubscriptionService', () => ({ isVenueBusinessLive: async (venue) => venue.live !== false }));
jest.mock('../venueHelpers', () => ({ venueGlobalPlaceId: async () => 'gp1' }));
jest.mock('../hiddenAccounts', () => ({ isHiddenAccount: (u) => u.isHiddenAccount === true }));
jest.mock('../storeCustomers', () => ({ countsFromLedger: async () => ({ purchases: 0, rewardsClaimed: 0, lastScanAt: null }) }));

const auto = require('../storeAutomations');

const NOW = new Date('2026-11-09T15:00:00.000Z'); // 10am New York
const daysAgo = (n) => new Date(NOW.getTime() - n * 86400000).toISOString();
const venue = { venueId: 'v1', venueName: "Sal's", earnRate: 25, offers: [{ offerId: 'o1', title: 'Free coffee', pointsCost: 100, active: true }] };
const on = { winBack: { enabled: true, days: 30, bonusPoints: 50 }, birthday: { enabled: true, bonusPoints: 20 }, almostThere: { enabled: true } };
const customer = (userId, extra = {}) => ({ userId, points: 0, purchases: 3, lastScanAt: daysAgo(3), removed: false, lastNudgeAt: null, birthday: null, timeZone: 'America/New_York', ...extra });

describe('settings', () => {
  it('fills defaults and refuses bad values', () => {
    expect(auto.settingsOf({})).toEqual(auto.DEFAULTS);
    expect(auto.settingsOf({ automations: { winBack: { enabled: true, days: 45, bonusPoints: -5 } } }).winBack).toEqual({ enabled: true, days: 30, bonusPoints: 0 });
    expect(auto.normalizeSettings({ winBack: { enabled: true, days: 60, bonusPoints: 50 }, almostThere: { enabled: true } }))
      .toEqual({ winBack: { enabled: true, days: 60, bonusPoints: 50 }, birthday: { enabled: false, bonusPoints: 0 }, almostThere: { enabled: true } });
    expect(() => auto.normalizeSettings({ winBack: { days: 45 } })).toThrow(/14, 30, 60, 90/);
    expect(() => auto.normalizeSettings({ birthday: { bonusPoints: 99999 } })).toThrow(/whole number/);
    expect(() => auto.normalizeSettings({ almostThere: { enabled: 'yes' } })).toThrow(/on or off/);
  });

  it('birthdays are a month and day', () => {
    expect(auto.normalizeBirthday('03-14')).toBe('03-14');
    expect(auto.normalizeBirthday(null)).toBeNull();
    expect(() => auto.normalizeBirthday('1990-03-14')).toThrow(/month and day/);
    expect(() => auto.normalizeBirthday('13-01')).toThrow();
  });
});

describe('planNudges', () => {
  it('wins back people quiet longer than the setting, once per quiet spell', () => {
    const plan = auto.planNudges({ venue, settings: on, now: NOW, customers: [
      customer('quiet', { lastScanAt: daysAgo(31) }),
      customer('recent', { lastScanAt: daysAgo(10) }),
      customer('never', { purchases: 0, lastScanAt: null })
    ] });
    expect(plan).toEqual([expect.objectContaining({ userId: 'quiet', type: 'winBack', key: `winBack_${daysAgo(31).slice(0, 10)}`, bonusPoints: 50 })]);
    expect(plan[0].message.body).toContain('+50 bonus points');
  });

  it('almost there: one more purchase reaches the cheapest reward', () => {
    const plan = auto.planNudges({ venue, settings: on, now: NOW, customers: [
      customer('close', { points: 80 }),   // 20 short, earn 25: one visit
      customer('far', { points: 40 }),     // 60 short: three visits
      customer('ready', { points: 120 })   // can redeem already
    ] });
    expect(plan.map((p) => p.userId)).toEqual(['close']);
    expect(plan[0]).toMatchObject({ type: 'almostThere', key: 'almost_80', bonusPoints: 0 });
    expect(plan[0].message.title).toBe('One more visit to a free coffee');
    expect(plan[0].message.body).toContain('20 points from a free coffee');
  });

  it('birthdays win over everything, in the customer\'s own day; one nudge per person', () => {
    const plan = auto.planNudges({ venue, settings: on, now: NOW, customers: [
      customer('bday', { birthday: '11-09', points: 80, lastScanAt: daysAgo(40) }),
      customer('tomorrow', { birthday: '11-10' })
    ] });
    expect(plan).toEqual([expect.objectContaining({ userId: 'bday', type: 'birthday', key: 'birthday_2026', bonusPoints: 20 })]);
  });

  it('leaves removed people and anyone nudged in the last 14 days alone; off switches plan nothing', () => {
    const plan = auto.planNudges({ venue, settings: on, now: NOW, customers: [
      customer('removed', { removed: true, lastScanAt: daysAgo(40) }),
      customer('justNudged', { lastNudgeAt: daysAgo(5), lastScanAt: daysAgo(40) }),
      customer('oldNudge', { lastNudgeAt: daysAgo(20), lastScanAt: daysAgo(40) })
    ] });
    expect(plan.map((p) => p.userId)).toEqual(['oldNudge']);
    expect(auto.planNudges({ venue, settings: auto.DEFAULTS, now: NOW, customers: [customer('x', { lastScanAt: daysAgo(90) })] })).toEqual([]);
  });
});

describe('applyPendingBonus', () => {
  it('pays a live bonus once and clears an expired one for nothing', () => {
    expect(auto.applyPendingBonus({}, NOW)).toEqual({ bonus: 0, consume: false });
    expect(auto.applyPendingBonus({ pendingBonus: { points: 50, expiresAt: daysAgo(-5) } }, NOW)).toEqual({ bonus: 50, consume: true });
    expect(auto.applyPendingBonus({ pendingBonus: { points: 50, expiresAt: daysAgo(1) } }, NOW)).toEqual({ bonus: 0, consume: true });
  });
});

describe('runDue', () => {
  beforeEach(async () => {
    mockPush.mockClear(); mockEmail.mockClear();
    mockDb.rows('stickerVenues').clear(); mockDb.rows('users').clear(); mockDb.rows('storeAutomationSends').clear();
    await mockDb.collection('stickerVenues').doc('v1').set({ ...venue, active: true, automations: on });
    await mockDb.collection('stickerVenues').doc('v2').set({ ...venue, venueName: 'Lapsed', active: true, live: false, automations: on });
    await mockDb.collection('users').doc('pushy').set({
      email: 'p@example.com', deviceTokens: [{ token: 't' }],
      rewardPointsByVenue: { v1: { points: 10, purchases: 2, lastScanAt: daysAgo(45), countsBackfilled: true } }
    });
    await mockDb.collection('users').doc('maily').set({
      email: 'm@example.com', deviceTokens: [],
      rewardPointsByVenue: { v1: { points: 10, purchases: 2, lastScanAt: daysAgo(45), countsBackfilled: true } }
    });
    await mockDb.collection('users').doc('muted').set({
      email: 'x@example.com', deviceTokens: [{ token: 't' }], notificationPreferences: { storeAlerts: false },
      rewardPointsByVenue: { v1: { points: 10, purchases: 2, lastScanAt: daysAgo(45), countsBackfilled: true } }
    });
  });

  it('a dry run lists what would go and touches nothing', async () => {
    const summary = await auto.runDue({ now: NOW, dryRun: true });
    expect(summary.venues).toBe(1);
    expect(summary.lapsed).toBe(1);
    expect(summary.would.map((w) => [w.userId, w.channel]).sort()).toEqual([['maily', 'email'], ['muted', null], ['pushy', 'push']]);
    expect(mockPush).not.toHaveBeenCalled();
    expect(mockDb.rows('storeAutomationSends').size).toBe(0);
  });

  it('sends by push or email, promises the bonus, and a rerun sends nothing again', async () => {
    const first = await auto.runDue({ now: NOW });
    expect(first.sent).toEqual({ push: 1, email: 1 });
    expect(first.unreachable).toBe(1);
    expect(mockPush).toHaveBeenCalledWith('pushy', expect.objectContaining({ type: 'store_nudge', title: "We miss you at Sal's", data: expect.objectContaining({ type: 'store_nudge', venueId: 'v1', placeId: 'gp1' }) }));
    expect(mockEmail).toHaveBeenCalledWith(expect.objectContaining({ to: 'm@example.com', subject: "We miss you at Sal's" }));
    expect(mockEmail.mock.calls[0][0].headers['List-Unsubscribe']).toContain('kind=storeNudges');
    const pushy = (await mockDb.collection('users').doc('pushy').get()).data().rewardPointsByVenue.v1;
    expect(pushy.lastNudgeAt).toBe(NOW.toISOString());
    expect(pushy.pendingBonus).toMatchObject({ points: 50, automation: 'winBack' });
    expect(mockDb.rows('storeAutomationSends').size).toBe(2);

    const again = await auto.runDue({ now: new Date(NOW.getTime() + 3600000) });
    expect(again.sent).toEqual({ push: 0, email: 0 });
    expect(mockPush).toHaveBeenCalledTimes(1);
  });

  it('a push dropped by quiet hours is deferred: nothing recorded, so tomorrow plans it again', async () => {
    mockPush.mockResolvedValueOnce({ success: false, error: 'Quiet hours' });
    const first = await auto.runDue({ now: NOW });
    expect(first.deferred).toBe(1);
    expect(first.sent).toEqual({ push: 0, email: 1 });
    const pushy = (await mockDb.collection('users').doc('pushy').get()).data().rewardPointsByVenue.v1;
    expect(pushy.lastNudgeAt).toBeUndefined();
    expect(pushy.pendingBonus).toBeUndefined();
    expect(mockDb.rows('storeAutomationSends').size).toBe(1);

    const tomorrow = await auto.runDue({ now: new Date(NOW.getTime() + 86400000) });
    expect(tomorrow.sent).toEqual({ push: 1, email: 0 });
    expect(mockDb.rows('storeAutomationSends').size).toBe(2);
  });

  it('stats count sends and who came back', async () => {
    await auto.runDue({ now: NOW });
    await mockDb.collection('users').doc('pushy').update('rewardPointsByVenue.v1.lastScanAt', daysAgo(-1));
    const stats = await auto.stats({ venueId: 'v1' });
    expect(stats.winBack).toEqual({ sent: 2, cameBack: 1 });
    expect(stats.birthday).toEqual({ sent: 0, cameBack: 0 });
  });
});
