// The retry classifier: only transient SMTP/network failures are retried.
process.env.EMAIL_SERVICE = 'custom';
delete process.env.SMTP_HOST; // constructor falls back to the mock transporter
const emailService = require('../emailService');
const EmailService = emailService.constructor;

describe('EmailService.isTransientSmtpError', () => {
  it('retries the host connection cap and greeting/socket failures', () => {
    expect(EmailService.isTransientSmtpError(new Error('Invalid greeting. response=421 Too many concurrent SMTP connections from this IP address; please try again later'))).toBe(true);
    expect(EmailService.isTransientSmtpError(Object.assign(new Error('boom'), { responseCode: 421 }))).toBe(true);
    expect(EmailService.isTransientSmtpError(new Error('read ECONNRESET'))).toBe(true);
    expect(EmailService.isTransientSmtpError(new Error('Connection timeout'))).toBe(true);
  });
  it('does not retry auth or recipient errors', () => {
    expect(EmailService.isTransientSmtpError(Object.assign(new Error('Invalid login: 535 Authentication failed'), { responseCode: 535 }))).toBe(false);
    expect(EmailService.isTransientSmtpError(Object.assign(new Error('550 No such user'), { responseCode: 550 }))).toBe(false);
  });
});

describe('sendWithRetry', () => {
  it('retries a transient failure then succeeds', async () => {
    const calls = [];
    emailService.transporter = {
      sendMail: jest.fn(async () => {
        calls.push(1);
        if (calls.length < 2) throw Object.assign(new Error('421 Too many concurrent SMTP connections'), { responseCode: 421 });
        return { messageId: 'ok' };
      })
    };
    jest.spyOn(global, 'setTimeout').mockImplementation((fn) => { fn(); return 0; });
    const result = await emailService.sendWithRetry({ to: 'x@y.z' });
    expect(result.messageId).toBe('ok');
    expect(calls.length).toBe(2);
    global.setTimeout.mockRestore();
  });
  it('gives up after the attempt budget', async () => {
    emailService.transporter = { sendMail: jest.fn(async () => { throw Object.assign(new Error('421 busy'), { responseCode: 421 }); }) };
    jest.spyOn(global, 'setTimeout').mockImplementation((fn) => { fn(); return 0; });
    await expect(emailService.sendWithRetry({ to: 'x@y.z' }, 3)).rejects.toThrow('421 busy');
    expect(emailService.transporter.sendMail).toHaveBeenCalledTimes(3);
    global.setTimeout.mockRestore();
  });
});

describe('SMTP fallback route (Amazon SES)', () => {
  afterEach(() => { emailService.fallbackTransporter = null; jest.restoreAllMocks(); });
  const refuse = () => { throw Object.assign(new Error('Invalid greeting. response=421 Too many concurrent SMTP connections'), { responseCode: 421 }); };

  it('sends through the fallback right away when the primary refuses', async () => {
    emailService.transporter = { sendMail: jest.fn(async () => refuse()) };
    emailService.fallbackTransporter = { sendMail: jest.fn(async () => ({ messageId: 'ses-1' })) };
    const info = await emailService.sendWithRetry({ to: 'a@b.com', subject: 's' });
    expect(info.messageId).toBe('ses-1');
    expect(emailService.transporter.sendMail).toHaveBeenCalledTimes(1);
  });

  it('a login failure on the primary also fails over', async () => {
    emailService.transporter = { sendMail: jest.fn(async () => { throw Object.assign(new Error('Invalid login: 535 Authentication failed'), { responseCode: 535 }); }) };
    emailService.fallbackTransporter = { sendMail: jest.fn(async () => ({ messageId: 'ses-2' })) };
    expect((await emailService.sendWithRetry({ to: 'a@b.com' })).messageId).toBe('ses-2');
  });

  it('a rejected recipient or a suppressed address does not fail over', async () => {
    emailService.fallbackTransporter = { sendMail: jest.fn(async () => ({ messageId: 'x' })) };
    emailService.transporter = { sendMail: jest.fn(async () => { throw Object.assign(new Error('550 No such user'), { responseCode: 550 }); }) };
    await expect(emailService.sendWithRetry({ to: 'a@b.com' })).rejects.toThrow('550');
    emailService.transporter = { sendMail: jest.fn(async () => { throw Object.assign(new Error('suppressed'), { code: 'SUPPRESSED' }); }) };
    await expect(emailService.sendWithRetry({ to: 'a@b.com' })).rejects.toThrow('suppressed');
    expect(emailService.fallbackTransporter.sendMail).not.toHaveBeenCalled();
  });

  it('without a fallback configured, the old retries still apply', async () => {
    jest.spyOn(global, 'setTimeout').mockImplementation((fn) => { fn(); return 0; });
    let n = 0;
    emailService.transporter = { sendMail: jest.fn(async () => { if (++n < 3) refuse(); return { messageId: 'third-time' }; }) };
    expect((await emailService.sendWithRetry({ to: 'a@b.com' })).messageId).toBe('third-time');
  });
});
