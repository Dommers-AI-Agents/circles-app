jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn() }));

const N = require('../messageEmailNudge');

const at = (iso) => new Date(iso);
const user = { email: 'pat@example.com', notificationPreferences: { timezone: 'America/New_York' } };
// 15:00Z = 10 am / 11 am in New York
const noon = at('2026-11-17T17:00:00Z');

describe('who gets an unread-message email, and when', () => {
  test('anyone with an email address, during the day', () => {
    expect(N.gate({ user, state: null, now: noon })).toEqual({ ok: true });
  });

  test('never test accounts, people without email, or people who unsubscribed', () => {
    expect(N.gate({ user: { ...user, isTestAccount: true }, state: null, now: noon })).toMatchObject({ ok: false, keep: false });
    expect(N.gate({ user: { ...user, email: '' }, state: null, now: noon })).toMatchObject({ ok: false, reason: 'no_email' });
    expect(N.gate({ user: { ...user, emailPreferences: { messageEmails: false } }, state: null, now: noon }))
      .toMatchObject({ ok: false, reason: 'unsubscribed', keep: false });
  });

  test('not between 10 pm and 8 am their time; it waits for the morning', () => {
    expect(N.gate({ user, state: null, now: at('2026-11-18T04:00:00Z') })).toMatchObject({ ok: false, reason: 'quiet_hours', keep: true });
    expect(N.gate({ user, state: null, now: at('2026-11-18T13:30:00Z') })).toEqual({ ok: true }); // 8:30 am
  });

  test('at most one an hour and four a day', () => {
    const justSent = { lastSentAt: at('2026-11-17T16:30:00Z').toISOString(), day: '2026-11-17', sentToday: 1 };
    expect(N.gate({ user, state: justSent, now: noon })).toMatchObject({ ok: false, reason: 'recently_emailed', keep: true });
    const capped = { lastSentAt: at('2026-11-17T14:00:00Z').toISOString(), day: '2026-11-17', sentToday: N.DAILY_CAP };
    expect(N.gate({ user, state: capped, now: noon })).toMatchObject({ ok: false, reason: 'daily_cap' });
    expect(N.gate({ user, state: { ...capped, day: '2026-11-16' }, now: noon })).toEqual({ ok: true });
  });

  test('the first email sets up one reminder a day later; the reminder is the last', () => {
    const first = N.nextForRow({ stage: 0 }, noon);
    expect(first.action).toBe('update');
    expect(Date.parse(first.data.dueAt) - noon.getTime()).toBe(N.REMINDER_AFTER);
    expect(N.nextForRow({ stage: 1 }, noon)).toEqual({ action: 'delete' });
  });

  test('sending counts toward the day', () => {
    expect(N.afterSend({ user, state: null, now: noon })).toMatchObject({ day: '2026-11-17', sentToday: 1 });
    expect(N.afterSend({ user, state: { day: '2026-11-17', sentToday: 2 }, now: noon }).sentToday).toBe(3);
  });
});

describe('the email', () => {
  const chat = { conversationId: 'c1', stage: 0, unread: 1, senderId: 's1', senderName: 'Brittany Sgroi', senderPhoto: null, firstUnreadAt: '2026-11-17T16:00:00Z' };

  test('names the sender like Snapchat does', () => {
    expect(N.subjectFor([chat])).toBe('Brittany Sgroi sent you a message');
    expect(N.subjectFor([{ ...chat, unread: 3 }])).toBe('Brittany Sgroi sent you 3 messages');
    expect(N.subjectFor([{ ...chat, groupName: 'Beach Crew' }])).toBe('Brittany Sgroi sent you a message in Beach Crew');
    expect(N.subjectFor([{ ...chat, stage: 1 }])).toBe('Brittany is waiting on your reply');
    expect(N.subjectFor([chat, { ...chat, conversationId: 'c2', senderName: 'Sal Romano', unread: 2 }]))
      .toBe('You have 3 unread messages from Brittany and Sal');
  });

  test('shows who and when, opens the chat, and never quotes the message', () => {
    const email = N.buildEmail({ chats: [chat], unsubscribe: 'https://x/unsub', now: noon });
    expect(email.html).toContain('/app/messages/c1');
    expect(email.html).toContain('Open chat');
    expect(email.html).toContain('1 hr ago');
    expect(email.html).toContain('>BS<'); // initials when there's no photo
    expect(email.html).toContain('https://x/unsub');
    const withPhoto = N.buildEmail({ chats: [{ ...chat, senderPhoto: 'https://img/p.jpg' }], unsubscribe: 'u', now: noon });
    expect(withPhoto.html).toContain('https://img/p.jpg');
  });

  test('several chats list each one and open Messages', () => {
    const email = N.buildEmail({ chats: [chat, { ...chat, conversationId: 'c2', senderName: 'Sal' }], unsubscribe: 'u', now: noon });
    expect(email.html).toContain('/app/messages/c1');
    expect(email.html).toContain('/app/messages/c2');
    expect(email.html).toContain('Open messages');
  });

  test('initials skip emoji', () => {
    expect(N.initials('Melinda 🧜‍♀️')).toBe('M');
    expect(N.initials('Brittany Sgroi')).toBe('BS');
  });
});
