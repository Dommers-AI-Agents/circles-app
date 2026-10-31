// Sign in or up with an emailed 6-digit code (App Clip, 2026-10-31)
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), getAuth: () => ({}) }));
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { createEmailCodeService, emailKey, MAX_TRIES } = require('../emailCodeService');

function setup({ users = [], authUsers = [] } = {}) {
  const db = new FakeFirestore({ namespaced: true });
  for (const u of users) db.rows('users').set(u.id, u);
  const sent = [];
  let clock = 1_000_000;
  let next = '123456';
  const auth = {
    created: [],
    async getUser(uid) { const u = authUsers.find((a) => a.uid === uid); if (!u) throw new Error('no user'); return u; },
    async getUserByEmail(email) { const u = authUsers.find((a) => a.email === email); if (!u) throw new Error('no user'); return u; },
    async createUser(data) { const u = { uid: `uid-${auth.created.length + 1}`, ...data }; auth.created.push(u); return u; }
  };
  const svc = createEmailCodeService({
    db, auth, secret: 'test-secret',
    now: () => clock,
    createCode: () => next,
    buildUser: (d) => ({ email: d.email, displayName: d.displayName, linkedProviders: d.linkedProviders, createdAt: 'now' }),
    sendCode: async (email, code) => { sent.push({ email, code }); }
  });
  return { db, svc, sent, auth, tick: (ms) => { clock += ms; }, setNext: (c) => { next = c; } };
}

describe('emailCodeService', () => {
  test('start emails a code, stores only its hash, and says whether the account is new', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }] });
    expect(await t.svc.start('  NEW@Example.com ')).toEqual({ newAccount: true });
    expect(t.sent).toEqual([{ email: 'new@example.com', code: '123456' }]);
    const row = t.db.rows('emailLoginCodes').get(emailKey('new@example.com'));
    expect(row.codeHash).toMatch(/^[0-9a-f]{64}$/);
    expect(JSON.stringify(row)).not.toMatch(/123456|new@example/);
    expect(await t.svc.start('old@example.com')).toEqual({ newAccount: false });
  });

  test('refuses bad emails and Apple private relays', async () => {
    const t = setup();
    await expect(t.svc.start('nope')).rejects.toMatchObject({ code: 'EMAIL_INVALID' });
    await expect(t.svc.start('x@privaterelay.appleid.com')).rejects.toMatchObject({ code: 'PRIVATE_RELAY_NOT_ALLOWED' });
  });

  test('five codes per email per hour', async () => {
    const t = setup();
    for (let i = 0; i < 5; i++) await t.svc.start('a@example.com');
    await expect(t.svc.start('a@example.com')).rejects.toMatchObject({ code: 'TOO_MANY_CODES', status: 429 });
    t.tick(60 * 60 * 1000 + 1);
    await expect(t.svc.start('a@example.com')).resolves.toEqual({ newAccount: true });
  });

  test('a new account needs a name, which costs no try; then the code creates it, passwordless and verified', async () => {
    const t = setup();
    await t.svc.start('new@example.com');
    await expect(t.svc.verify({ email: 'new@example.com', code: '123456' })).rejects.toMatchObject({ code: 'NAME_REQUIRED' });
    const { user, isNew } = await t.svc.verify({ email: 'new@example.com', code: '123456', displayName: 'Sam' });
    expect(isNew).toBe(true);
    expect(user).toMatchObject({ id: 'uid-1', email: 'new@example.com', displayName: 'Sam', linkedProviders: { emailCode: 'uid-1' } });
    expect(t.auth.created[0]).toEqual({ uid: 'uid-1', email: 'new@example.com', emailVerified: true, displayName: 'Sam' });
    expect(t.db.rows('users').get('uid-1').email).toBe('new@example.com');
  });

  test('an existing account signs in with the code; the code works once', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com', displayName: 'Old' }], authUsers: [{ uid: 'u1', email: 'old@example.com' }] });
    await t.svc.start('old@example.com');
    const { user, isNew } = await t.svc.verify({ email: 'old@example.com', code: '123 456' });
    expect(isNew).toBe(false);
    expect(user.id).toBe('u1');
    await expect(t.svc.verify({ email: 'old@example.com', code: '123456' })).rejects.toMatchObject({ code: 'CODE_EXPIRED' });
  });

  test('a disabled account is refused even with the right code', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }], authUsers: [{ uid: 'u1', email: 'old@example.com', disabled: true }] });
    await t.svc.start('old@example.com');
    await expect(t.svc.verify({ email: 'old@example.com', code: '123456' })).rejects.toMatchObject({ code: 'ACCOUNT_DISABLED' });
  });

  test('codes expire after 10 minutes', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }] });
    await t.svc.start('old@example.com');
    t.tick(10 * 60 * 1000);
    await expect(t.svc.verify({ email: 'old@example.com', code: '123456' })).rejects.toMatchObject({ code: 'CODE_EXPIRED' });
  });

  test('five wrong tries lock the code, even against the right one; a new code starts over', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }] });
    await t.svc.start('old@example.com');
    for (let i = 1; i < MAX_TRIES; i++) {
      await expect(t.svc.verify({ email: 'old@example.com', code: '000000' })).rejects.toMatchObject({ code: 'CODE_INVALID' });
    }
    await expect(t.svc.verify({ email: 'old@example.com', code: '000000' })).rejects.toMatchObject({ code: 'TOO_MANY_TRIES', status: 429 });
    await expect(t.svc.verify({ email: 'old@example.com', code: '123456' })).rejects.toMatchObject({ code: 'TOO_MANY_TRIES' });
    t.setNext('654321');
    await t.svc.start('old@example.com');
    await expect(t.svc.verify({ email: 'old@example.com', code: '654321' })).resolves.toMatchObject({ isNew: false });
  });

  test('a new code replaces the old one', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }] });
    await t.svc.start('old@example.com');
    t.setNext('222222');
    await t.svc.start('old@example.com');
    await expect(t.svc.verify({ email: 'old@example.com', code: '123456' })).rejects.toMatchObject({ code: 'CODE_INVALID' });
    await expect(t.svc.verify({ email: 'old@example.com', code: '222222' })).resolves.toMatchObject({ isNew: false });
  });

  test('a half-created Auth record for the email is finished, not duplicated', async () => {
    const t = setup({ authUsers: [{ uid: 'half', email: 'new@example.com' }] });
    await t.svc.start('new@example.com');
    const { user } = await t.svc.verify({ email: 'new@example.com', code: '123456', displayName: 'Sam' });
    expect(user.id).toBe('half');
    expect(t.auth.created).toEqual([]);
  });
});
