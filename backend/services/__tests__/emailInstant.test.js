// Instant email sign-up for the App Clip and confirming the email later
// (Wes, 2026-10-31: "I want it to be instant")
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), getAuth: () => ({}) }));
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { createEmailCodeService, nameFromEmail, claimForVerifiedOwner, MAX_INSTANT_PER_IP_HOUR } = require('../emailCodeService');

function setup({ users = [], authUsers = [] } = {}) {
  const db = new FakeFirestore({ namespaced: true });
  for (const u of users) db.rows('users').set(u.id, u);
  const sent = [];
  const clock = 5_000_000;
  const auth = {
    created: [],
    updated: [],
    async getUser(uid) { const u = authUsers.find((a) => a.uid === uid); if (!u) throw new Error('no user'); return u; },
    async getUserByEmail(email) { const u = authUsers.find((a) => a.email === email); if (!u) throw new Error('no user'); return u; },
    async createUser(data) { const u = { uid: `uid-${auth.created.length + 1}`, ...data }; auth.created.push(u); return u; },
    async updateUser(uid, data) { auth.updated.push({ uid, ...data }); }
  };
  const svc = createEmailCodeService({
    db, auth, secret: 'test-secret',
    now: () => clock,
    createCode: () => '123456',
    buildUser: (d) => ({ email: d.email, displayName: d.displayName, linkedProviders: d.linkedProviders, createdAt: 'now' }),
    sendCode: async (email, code) => { sent.push({ email, code }); }
  });
  return { db, svc, sent, auth };
}

describe('instant sign-up', () => {
  test('a new email gets an account right away, unconfirmed, named from the email', async () => {
    const t = setup();
    const user = await t.svc.instant({ email: 'Jane.Doe+clip2@Example.com', ip: '1.2.3.4' });
    expect(user).toMatchObject({ id: 'uid-1', email: 'jane.doe+clip2@example.com', displayName: 'Jane Doe', emailUnverified: true, linkedProviders: { emailInstant: 'uid-1' } });
    expect(t.auth.created[0]).toMatchObject({ emailVerified: false });
    expect(t.db.rows('users').get('uid-1').emailUnverified).toBe(true);
    expect(t.sent).toEqual([]); // no code, no welcome mail yet
  });

  test('an email that has an account gets a code, never a session', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'old@example.com' }] });
    await expect(t.svc.instant({ email: 'old@example.com', ip: '1.2.3.4' })).rejects.toMatchObject({ status: 409, code: 'VERIFY_REQUIRED' });
    expect(t.sent).toEqual([{ email: 'old@example.com', code: '123456' }]);
    expect(t.auth.created).toEqual([]);
  });

  test('an Auth record with no user doc also counts as existing', async () => {
    const t = setup({ authUsers: [{ uid: 'a1', email: 'half@example.com' }] });
    await expect(t.svc.instant({ email: 'half@example.com', ip: '1.2.3.4' })).rejects.toMatchObject({ code: 'VERIFY_REQUIRED' });
  });

  test('bad emails and relays are refused', async () => {
    const t = setup();
    await expect(t.svc.instant({ email: 'nope', ip: '1' })).rejects.toMatchObject({ code: 'EMAIL_INVALID' });
    await expect(t.svc.instant({ email: 'x@privaterelay.appleid.com', ip: '1' })).rejects.toMatchObject({ code: 'PRIVATE_RELAY_NOT_ALLOWED' });
  });

  test(`at most ${MAX_INSTANT_PER_IP_HOUR} per IP per hour`, async () => {
    const t = setup();
    for (let i = 0; i < MAX_INSTANT_PER_IP_HOUR; i++) await t.svc.instant({ email: `p${i}x@example.com`, ip: '9.9.9.9' });
    await expect(t.svc.instant({ email: 'one.more@example.com', ip: '9.9.9.9' })).rejects.toMatchObject({ status: 429, code: 'TOO_MANY_SIGNUPS' });
    await expect(t.svc.instant({ email: 'other@example.com', ip: '8.8.8.8' })).resolves.toMatchObject({ email: 'other@example.com' });
  });

  test('a typed name wins over the email-derived one', async () => {
    const t = setup();
    expect((await t.svc.instant({ email: 'x1@example.com', displayName: 'Sam Lee', ip: '1' })).displayName).toBe('Sam Lee');
  });
});

describe('names from emails', () => {
  test.each([
    ['jane.doe+x@example.com', 'Jane Doe'],
    ['jsmith88@example.com', 'Jsmith'],
    ['mary_ann-o@example.com', 'Mary Ann O'],
    ['12345@example.com', 'Friend'],
    ['a@example.com', 'Friend']
  ])('%s → %s', (email, name) => expect(nameFromEmail(email)).toBe(name));
});

describe('confirming later', () => {
  test('a code sign-in to an unconfirmed account confirms it and voids older sessions', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'inst@example.com', emailUnverified: true }], authUsers: [{ uid: 'u1', email: 'inst@example.com' }] });
    await t.svc.start('inst@example.com');
    const result = await t.svc.verify({ email: 'inst@example.com', code: '123456' });
    expect(result).toMatchObject({ isNew: false, confirmedNow: true });
    const row = t.db.rows('users').get('u1');
    expect(row.emailUnverified).toBe(false);
    expect(row.sessionsValidAfter).toBe(5_000_000);
    expect(t.auth.updated).toEqual([{ uid: 'u1', emailVerified: true }]);
  });

  test('a confirmed account signs in without a claim', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'ok@example.com' }], authUsers: [{ uid: 'u1', email: 'ok@example.com' }] });
    await t.svc.start('ok@example.com');
    const result = await t.svc.verify({ email: 'ok@example.com', code: '123456' });
    expect(result.confirmedNow).toBe(false);
    expect(t.db.rows('users').get('u1').sessionsValidAfter).toBeUndefined();
  });

  test('the signed-in owner confirms their own email and keeps their sessions', async () => {
    const t = setup({ users: [{ id: 'u1', email: 'inst@example.com', emailUnverified: true }] });
    await t.svc.start('inst@example.com');
    await expect(t.svc.confirm({ userId: 'u1', email: 'inst@example.com', code: '000000' })).rejects.toMatchObject({ code: 'CODE_INVALID' });
    expect(await t.svc.confirm({ userId: 'u1', email: 'inst@example.com', code: '123456' })).toEqual({ confirmedNow: true });
    const row = t.db.rows('users').get('u1');
    expect(row.emailUnverified).toBe(false);
    expect(row.sessionsValidAfter).toBeUndefined();
  });

  test('a provider-verified sign-in claims an unconfirmed account (Apple same email)', () => {
    expect(claimForVerifiedOwner({ emailUnverified: true }, 42)).toEqual({ emailUnverified: false, sessionsValidAfter: 42 });
    expect(claimForVerifiedOwner({ emailUnverified: false }, 42)).toEqual({});
    expect(claimForVerifiedOwner({}, 42)).toEqual({});
  });
});
