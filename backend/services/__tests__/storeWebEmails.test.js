// Store emails for customers with no app (2026-11-26): who is web-only, the
// per-store stop link, the welcome, and a store's alert as an email.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn() }));
jest.mock('../followSuggestionEmailService', () => ({ unsubscribeUrl: (uid, kind) => `https://x/unsub?uid=${uid}&kind=${kind}` }));

const web = require('../storeWebEmails');
const { decide, buildSingle, DAILY_CAP } = require('../emailFallback');
const { isStoreWebSignup, isClipSignup } = require('../newAccountService');

const user = { email: 'pat@example.com', notificationPreferences: { timezone: 'America/New_York' } };
const alert = (extra = {}) => ({
  type: 'store_alert', title: 'Demo Cafe: Half-price wine tonight', body: 'Bottles are half off after 5.',
  data: { type: 'store_alert', placeId: 'gp1', kind: 'announcement', storeCode: 'win123', storeName: 'Demo <Cafe>', headline: 'Half-price wine tonight', message: 'Bottles are half off after 5.', ...extra }
});

test('web-only means joined on the store page and never had the app', () => {
  expect(web.isWebOnly({ acquisitionSource: 'store_web' })).toBe(true);
  expect(web.isWebOnly({ acquisitionSource: 'store_web', deviceTokens: [{ token: 't' }] })).toBe(false);
  expect(web.isWebOnly({ acquisitionSource: 'store_web', clipInstallConvertedAt: '2026-11-26' })).toBe(false);
  expect(web.isWebOnly({ acquisitionSource: 'app_clip' })).toBe(false);
  expect(web.isWebOnly({})).toBe(false);
});

test('a web sign-up is its own source, never counted as the clip', () => {
  expect(isStoreWebSignup({ signupSource: 'store_web', stickerCode: 'WIN123' })).toBe(true);
  expect(isStoreWebSignup({ signupSource: 'store_web', stickerCode: 'nope' })).toBe(false);
  expect(isClipSignup({ signupSource: 'store_web', stickerCode: 'WIN123' })).toBe(false);
});

test('the stop link names one store, and only a well-formed one reads back', () => {
  expect(web.stopUrl('u1', 'gp1')).toBe('https://x/unsub?uid=u1&kind=store:gp1');
  expect(web.placeFromStopKind('store:gp1')).toBe('gp1');
  expect(web.placeFromStopKind('storeNudges')).toBeNull();
  expect(web.placeFromStopKind('store:../users')).toBeNull();
  expect(web.storePageUrl('win123')).toBe('https://api.favcircles.com/s/WIN123?web=1');
});

describe("a store's alert by email", () => {
  test('goes to a follower a push cannot reach, with the store page behind the button', () => {
    const out = decide({ notification: alert(), user, state: null });
    expect(out.action).toBe('send');
    expect(out.item.line).toBe('Demo <Cafe>: Half-price wine tonight');
    expect(out.item.detail).toBe('Bottles are half off after 5.');
    expect(out.item.url).toBe('https://api.favcircles.com/s/WIN123?web=1');
    const mail = buildSingle({ userId: 'u1', item: out.item, buttonLabel: out.button });
    expect(mail.html).toContain('Demo &lt;Cafe&gt;: Half-price wine tonight');
    expect(mail.html).toContain('href="https://x/unsub?uid=u1&kind=store:gp1"');
    expect(mail.html).toContain('Stop emails from this store');
    expect(mail.html).toContain('kind=storeNudges');
    expect(mail.html).not.toContain('notifications are off');
    expect(mail.unsubscribe).toBe('https://x/unsub?uid=u1&kind=store:gp1');
  });

  test("does not use up the day's other emails or wait for the round-up", () => {
    const full = { day: '2026-11-26', sentToday: DAILY_CAP };
    const out = decide({ notification: alert(), user, state: full, now: new Date('2026-11-26T15:00:00Z') });
    expect(out.action).toBe('send');
    expect(out.next.sentToday).toBe(DAILY_CAP);
    expect(out.next.pending).toBeUndefined();
  });

  test('a new reward reads as one; people with the app, opted out, hidden or on a relay address get none', () => {
    expect(decide({ notification: alert({ kind: 'offer', headline: 'Free coffee', message: undefined }), user, state: null }).item.detail).toBe('New reward');
    expect(decide({ notification: alert(), user: { ...user, deviceTokens: [{ token: 't' }] }, state: null }).reason).toBe('push_reachable');
    expect(decide({ notification: alert(), user: { ...user, emailPreferences: { storeNudges: false } }, state: null }).reason).toBe('unsubscribed');
    // The followers-and-comments switch is a different one
    expect(decide({ notification: alert(), user: { ...user, emailPreferences: { activityEmails: false } }, state: null }).action).toBe('send');
    expect(decide({ notification: alert(), user: { ...user, isTestAccount: true }, state: null }).reason).toBe('hidden_account');
    expect(decide({ notification: alert(), user: { ...user, email: 'x@privaterelay.appleid.com' }, state: null }).reason).toBe('relay_address');
  });
});

test('the welcome says what they got and how to get back, escaped', () => {
  const mail = web.buildWelcome({
    store: { name: 'Demo <Cafe>', photoUrl: 'https://img/c.jpg', pageUrl: web.storePageUrl('WIN123') },
    awardedPoints: 25, rewards: { earnRate: 10, balance: 25, offers: [{ title: 'Free coffee', pointsCost: 50 }] },
    coupon: { title: '20% off' }, stop: web.stopUrl('u1', 'gp1')
  });
  expect(mail.subject).toBe("You're in at Demo <Cafe>. +25 points.");
  expect(mail.html).toContain('You&#39;re in at Demo &lt;Cafe&gt;. +25 points.');
  expect(mail.html).toContain('href="https://api.favcircles.com/s/WIN123?web=1"');
  expect(mail.html).toContain('Free coffee');
  expect(mail.html).toContain('Your coupon:</b> 20% off');
  expect(mail.html).toContain('Stop emails from this store');
  const plain = web.buildWelcome({ store: { name: 'Demo Cafe', pageUrl: 'x' } });
  expect(plain.subject).toBe("You're in at Demo Cafe.");
  expect(plain.html).not.toMatch(/\d+ points/);
});
