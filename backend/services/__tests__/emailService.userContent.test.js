// User-typed values in outgoing mail (security audit 2026-10-01): escaped in
// HTML, single-line subjects, the kill switch for user-triggered mail, and
// connection-request emails spending the requester's budget.
process.env.EMAIL_SERVICE = 'custom';
delete process.env.SMTP_HOST; // mock transporter

const mockConsumeEmail = jest.fn(async () => ({ allowed: true, used: 1, limit: 25 }));
jest.mock('../dailyBudget', () => ({ consumeEmail: (...args) => mockConsumeEmail(...args) }));

const emailService = require('../emailService');

let sent;
beforeEach(() => {
  sent = [];
  emailService.transporter = { sendMail: jest.fn(async (opts) => { sent.push(opts); return { messageId: 'm1' }; }) };
  delete process.env.EMAIL_SENDING_DISABLED;
  mockConsumeEmail.mockClear();
});

const EVIL = 'Wes <a href="https://phish.example">click</a>\r\nBcc: victim@example.com';

test('app invitation escapes the inviter and recipient names and keeps the subject on one line', async () => {
  await emailService.sendAppInvitation('friend@example.com', EVIL, '<img src=x onerror=alert(1)>', 'https://api.favcircles.com/connect/wes');
  const [mail] = sent;
  expect(mail.html).not.toMatch(/<a href="https:\/\/phish/);
  expect(mail.html).not.toMatch(/<img src=x/);
  expect(mail.html).toMatch(/&lt;a href=&quot;https:\/\/phish\.example&quot;&gt;/);
  expect(mail.subject).not.toMatch(/[\r\n]/);
  // Plain text stays readable (no entities)
  expect(mail.text).toMatch(/<img src=x/);
});

test('connection request email escapes the name (budget is spent by the controller, not here)', async () => {
  await emailService.sendConnectionRequestEmail('wes@example.com', EVIL, 'sal');
  // Onboarding's welcome requests reuse this template and must not be throttled
  expect(mockConsumeEmail).not.toHaveBeenCalled();
  expect(sent[0].html).not.toMatch(/<a href="https:\/\/phish/);
  expect(sent[0].subject).not.toMatch(/[\r\n]/);
});

test('postcard escapes the place name, sender and note', async () => {
  await emailService.sendPostcardEmail('friend@example.com', {
    senderName: '<b>Sal</b>', imageUrl: 'https://x/img.jpg', message: '<script>x</script>',
    pageUrl: 'https://favcircles.com/p/1', placeName: '<i>Cafe</i>', placeCity: 'Charlotte'
  });
  expect(sent[0].html).not.toMatch(/<script>|<b>Sal|<i>Cafe/);
});

test('EMAIL_SENDING_DISABLED stops user-triggered mail only', async () => {
  process.env.EMAIL_SENDING_DISABLED = 'true';
  await emailService.sendAppInvitation('friend@example.com', 'Wes', null, null);
  await emailService.sendPostcardEmail('friend@example.com', { senderName: 'Sal', imageUrl: 'u', pageUrl: 'p' });
  expect(sent).toHaveLength(0);
  // Account mail keeps flowing
  await emailService.sendPasswordResetEmail('wes@example.com', 'https://reset', 'Wes');
  expect(sent).toHaveLength(1);
});
