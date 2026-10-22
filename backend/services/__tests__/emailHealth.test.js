const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');
const health = require('../emailHealth');

const setup = () => {
  const db = new FakeFirestore({ namespaced: true });
  const alerts = [];
  return { db, alerts, deps: { db, FieldValue: FakeFieldValue, adminAlerts: { alertAdmin: (a) => { alerts.push(a); return Promise.resolve(true); } } } };
};

test('counts each outcome per day, keeps failure detail, alerts on failures and fallbacks', async () => {
  const { db, alerts, deps } = setup();
  await health.record('primary', { to: 'a@b.com', subject: 'Hi' }, deps);
  await health.record('primary', { to: 'a@b.com' }, deps);
  await health.record('suppressed', { to: 'x@b.com' }, deps);
  await health.record('fallback', { to: 'wesley@favcircles.com', subject: 'Welcome', primaryError: '421 Too many' }, deps);
  await health.record('failed', { to: 'sal@example.com', subject: 'Reset', error: new Error('ETIMEDOUT') }, deps);
  const day = (await db.collection('emailStats').doc(health.dayKey()).get()).data();
  expect(day).toMatchObject({ primarySent: 2, suppressed: 1, fallbackSent: 1, failed: 1 });
  expect(day.recentFailures[0]).toMatchObject({ to: 'sa***@example.com', subject: 'Reset', error: 'ETIMEDOUT' });
  expect(day.recentFallbacks[0].error).toBe('421 Too many');
  expect(alerts.map((a) => a.key)).toEqual(['email_primary_down', 'email_failing']);
  expect(alerts[1].email).toBe(false); // email may be the broken thing — push only
});

test('dashboard shows live route checks and a zero-filled day series', async () => {
  const { db, deps } = setup();
  await health.record('primary', { to: 'a@b.com' }, deps);
  const emailService = {
    transporter: { verify: async () => true },
    fallbackTransporter: { verify: async () => { throw new Error('535 Authentication failed'); } }
  };
  const out = await health.dashboard({ days: 3 }, { db, emailService });
  expect(out.status.primary).toMatchObject({ configured: true, ok: true });
  expect(out.status.fallback).toMatchObject({ configured: true, ok: false, error: '535 Authentication failed' });
  expect(out.byDay).toHaveLength(3);
  expect(out.today.primarySent).toBe(1);
});

const withHosts = async (main, backup, fn) => {
  const saved = { main: process.env.SMTP_HOST, backup: process.env.SMTP_FALLBACK_HOST };
  process.env.SMTP_HOST = main;
  process.env.SMTP_FALLBACK_HOST = backup;
  try { await fn(); } finally {
    if (saved.main === undefined) delete process.env.SMTP_HOST; else process.env.SMTP_HOST = saved.main;
    if (saved.backup === undefined) delete process.env.SMTP_FALLBACK_HOST; else process.env.SMTP_FALLBACK_HOST = saved.backup;
  }
};
const SES = 'email-smtp.us-east-2.amazonaws.com';
const GODADDY = 'mail.favcircles.com';

test('hourly check alerts when the main route cannot log in, naming each route by host', () => withHosts(SES, GODADDY, async () => {
  const { alerts, deps } = setup();
  const emailService = { transporter: { verify: async () => { throw new Error('ECONNREFUSED'); } }, fallbackTransporter: { verify: async () => true } };
  await health.healthCheck({ ...deps, emailService });
  expect(alerts.map((a) => a.key)).toEqual(['email_check_primary']);
  expect(alerts[0].body).toContain('Amazon SES');
  expect(alerts[0].body).toContain('mail.favcircles.com backup is working');
}));

test('a backup that misses one hourly check is a blip; three in a row alert, and an answer resets the count', () => withHosts(SES, GODADDY, async () => {
  const { alerts, deps } = setup();
  let backupUp = false;
  const emailService = {
    transporter: { verify: async () => true },
    fallbackTransporter: { verify: async () => { if (!backupUp) throw new Error('Connection timeout'); return true; } }
  };
  const check = () => health.healthCheck({ ...deps, emailService });
  await check(); await check();
  expect(alerts).toEqual([]);
  backupUp = true; await check();
  backupUp = false; await check(); await check();
  expect(alerts).toEqual([]);
  await check();
  expect(alerts.map((a) => a.key)).toEqual(['email_check_fallback']);
  expect(alerts[0].body).toContain('mail.favcircles.com');
  expect(alerts[0].body).toContain('Failed 3 hourly checks in a row');
}));

test('the fallback alert names the routes from their hosts', () => withHosts(SES, GODADDY, async () => {
  const { alerts, deps } = setup();
  await health.record('fallback', { to: 'a@b.com', primaryError: 'Connection timeout' }, deps);
  expect(alerts[0].title).toBe('Main mail route is refusing — mail.favcircles.com backup is sending');
  expect(alerts[0].body).toContain('Amazon SES refused');
}));
