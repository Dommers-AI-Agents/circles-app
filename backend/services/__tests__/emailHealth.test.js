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

test('hourly check alerts when a route cannot log in', async () => {
  const { alerts, deps } = setup();
  const emailService = { transporter: { verify: async () => { throw new Error('ECONNREFUSED'); } }, fallbackTransporter: { verify: async () => true } };
  await health.healthCheck({ ...deps, emailService });
  expect(alerts.map((a) => a.key)).toEqual(['email_check_primary']);
  expect(alerts[0].body).toContain('SES backup is working');
});
