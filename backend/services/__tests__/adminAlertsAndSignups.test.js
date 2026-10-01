const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { alertAdmin } = require('../adminAlerts');
const { recordSignup, isDisposable } = require('../signupMonitor');

const deps = () => {
  const db = new FakeFirestore({ namespaced: true });
  const sent = { emails: [], pushes: [] };
  return {
    db, sent,
    emailService: { sendEmail: async (m) => { sent.emails.push(m); } },
    notificationService: { sendToUserWithRecord: async (uid, n) => { sent.pushes.push({ uid, n }); } }
  };
};

test('alertAdmin de-duplicates by key within the interval and reports the repeats', async () => {
  const d = deps();
  await d.db.collection('users').doc('admin1').set({ email: 'sgroiwes@gmail.com' });
  expect(await alertAdmin({ key: 'k', title: 'T', body: 'B' }, d)).toBe(true);
  expect(await alertAdmin({ key: 'k', title: 'T', body: 'B' }, d)).toBe(false);
  expect(d.sent.emails).toHaveLength(1);
  expect(d.sent.pushes[0]).toMatchObject({ uid: 'admin1', n: { type: 'admin_alert', title: 'T' } });
  // interval 0 = always send
  expect(await alertAdmin({ key: 'r', title: 'R', body: 'x', minIntervalMs: 0 }, d)).toBe(true);
  expect(await alertAdmin({ key: 'r', title: 'R', body: 'x', minIntervalMs: 0 }, d)).toBe(true);
});

test('signup monitor alerts on a burst from one IP and on throwaway domains, never throws', async () => {
  const d = deps();
  const alerts = [];
  const adminAlerts = { alertAdmin: (a) => { alerts.push(a); return Promise.resolve(true); } };
  process.env.SIGNUP_BURST_THRESHOLD = '3';
  for (let i = 0; i < 4; i++) await recordSignup({ ip: '1.2.3.4', email: `u${i}@gmail.com`, userId: `u${i}` }, { db: d.db, adminAlerts });
  expect(alerts.filter((a) => a.key.startsWith('signup_burst_'))).toHaveLength(1);
  await recordSignup({ ip: '9.9.9.9', email: 'x@mailinator.com', userId: 'x' }, { db: d.db, adminAlerts });
  expect(alerts.some((a) => a.key === 'signup_disposable_x')).toBe(true);
  expect(isDisposable('a@gmail.com')).toBe(false);
  await expect(recordSignup({ ip: '1.1.1.1', email: 'a@b.com', userId: 'y' }, { db: null, adminAlerts })).resolves.toBeUndefined();
  delete process.env.SIGNUP_BURST_THRESHOLD;
});
