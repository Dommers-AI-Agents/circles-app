jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn() }));
jest.mock('../followSuggestionEmailService', () => ({ unsubscribeUrl: (uid, kind) => `https://x/unsub?uid=${uid}&kind=${kind}` }));

const { pushReachable, decide, buildSingle, buildDigest, DAILY_CAP } = require('../emailFallback');

const token = [{ token: 't', platform: 'ios' }];
const base = { email: 'pat@example.com', notificationPreferences: { timezone: 'America/New_York' } };
const msg = (conversationId = 'c1') => ({ type: 'new_message', title: '💬 Brittany R', body: 'secret dinner plans', data: { conversationId, senderId: 's' } });
const at = (iso) => new Date(iso);

describe('who a push can reach', () => {
  test('no token, or notifications off, means email', () => {
    expect(pushReachable({ ...base })).toBe(false);
    expect(pushReachable({ ...base, deviceTokens: token, pushStatus: { status: 'denied' } })).toBe(false);
    expect(pushReachable({ ...base, deviceTokens: token, pushStatus: { status: 'notDetermined' } })).toBe(false);
  });
  test('allowed, or an older build that never reported, means push', () => {
    expect(pushReachable({ ...base, deviceTokens: token, pushStatus: { status: 'authorized' } })).toBe(true);
    expect(pushReachable({ ...base, deviceTokens: token, pushStatus: { status: 'provisional' } })).toBe(true);
    expect(pushReachable({ ...base, deviceTokens: token })).toBe(true);
  });
});

describe('deciding', () => {
  test('push-reachable people and non-listed types never email', () => {
    expect(decide({ notification: msg(), user: { ...base, deviceTokens: token }, state: null }).action).toBe('skip');
    expect(decide({ notification: { type: 'place_like', title: 'x' }, user: base, state: null }).reason).toBe('type_not_emailed');
    expect(decide({ notification: msg(), user: { ...base, emailPreferences: { activityEmails: false } }, state: null }).reason).toBe('unsubscribed');
    expect(decide({ notification: msg(), user: { ...base, email: '' }, state: null }).reason).toBe('no_email');
  });

  test('one email per conversation per 3 hours, but a different conversation still emails', () => {
    const first = decide({ notification: msg('c1'), user: base, state: null, now: at('2026-10-01T15:00:00Z') });
    expect(first.action).toBe('send');
    const again = decide({ notification: msg('c1'), user: base, state: first.next, now: at('2026-10-01T16:00:00Z') });
    expect(again).toMatchObject({ action: 'skip', reason: 'recently_emailed_about_this' });
    const other = decide({ notification: msg('c2'), user: base, state: first.next, now: at('2026-10-01T16:00:00Z') });
    expect(other.action).toBe('send');
    const later = decide({ notification: msg('c1'), user: base, state: other.next, now: at('2026-10-01T18:30:00Z') });
    expect(later.action).toBe('send');
  });

  test(`after ${DAILY_CAP} emails in a day the rest wait for the evening; a new day starts over`, () => {
    let state = null;
    const results = [];
    for (let i = 0; i < 5; i++) {
      const r = decide({ notification: { type: 'new_follower', body: `Person ${i} started following you`, data: { fromUserId: `u${i}` } },
        user: base, state, now: at('2026-10-01T14:00:00Z') });
      results.push(r.action);
      state = r.next;
    }
    expect(results).toEqual(['send', 'send', 'send', 'queue', 'queue']);
    expect(state.pending).toHaveLength(2);
    const tomorrow = decide({ notification: { type: 'new_follower', body: 'x', data: { fromUserId: 'z' } },
      user: base, state, now: at('2026-10-02T14:00:00Z') });
    expect(tomorrow.action).toBe('send');
    expect(tomorrow.next.pending).toHaveLength(2); // still waiting for the round-up
  });
});

describe('the emails', () => {
  test('a message email names the sender but never quotes the message', () => {
    const r = decide({ notification: msg(), user: base, state: null });
    const email = buildSingle({ userId: 'u1', item: r.item, buttonLabel: r.button });
    expect(email.subject).toBe('Brittany R sent you a message');
    expect(email.html).not.toContain('secret dinner plans');
    expect(email.text).not.toContain('secret dinner plans');
    expect(email.html).toContain('kind=activityEmails');
    expect(email.html).toContain('notifications are off');
  });

  test('a comment email links to the place and quotes the comment', () => {
    const r = decide({ notification: { type: 'place_comment', title: 'Sal commented on STIR', body: 'Best patio in town', data: { placeId: 'p9' } }, user: base, state: null });
    const email = buildSingle({ userId: 'u1', item: r.item, buttonLabel: r.button });
    expect(email.subject).toBe('Sal commented on STIR');
    expect(email.html).toContain('/place/p9');
    expect(email.html).toContain('Best patio in town');
  });

  test('the round-up lists every waiting item', () => {
    const items = [{ line: 'A followed you', url: 'https://x/a' }, { line: 'B followed you', url: 'https://x/b' }];
    const email = buildDigest({ userId: 'u1', items });
    expect(email.subject).toBe('2 more updates from FavCircles today');
    expect(email.html).toContain('A followed you');
    expect(email.html).toContain('B followed you');
  });
});
