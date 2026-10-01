// What makes a connection request acceptable on the spot, and how often the
// target hears about it (security audit 2026-10-01).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

process.env.JWT_SECRET = 'test-secret';
delete process.env.INVITE_TOKEN_SECRET;
const policy = require('../connectionRequestPolicy');

beforeEach(() => {
  mockDb.rows('connectionInvites').clear();
  mockDb.rows('connectionRequestLog').clear();
});

describe('invite tokens', () => {
  test('a token verifies only for the user it was signed for', () => {
    const token = policy.signInviteToken('wes');
    expect(token).toHaveLength(32);
    expect(policy.verifyInviteToken(token, 'wes')).toBe(true);
    expect(policy.verifyInviteToken(token, 'britt')).toBe(false);
    expect(policy.verifyInviteToken(undefined, 'wes')).toBe(false);
    expect(policy.verifyInviteToken('x'.repeat(32), 'wes')).toBe(false);
  });

  test('dotted legacy ids sign the same as the simple uid', () => {
    expect(policy.signInviteToken('000454.wes.2127')).toBe(policy.signInviteToken('wes'));
  });

  test('a dedicated secret changes (revokes) every token', () => {
    const before = policy.signInviteToken('wes');
    process.env.INVITE_TOKEN_SECRET = 'rotated';
    try {
      expect(policy.verifyInviteToken(before, 'wes')).toBe(false);
    } finally {
      delete process.env.INVITE_TOKEN_SECRET;
    }
  });
});

describe('emailed invites', () => {
  test('an invite to an address lets that address connect, case-insensitively', async () => {
    await policy.recordEmailInvite('wes', 'Friend@Example.com');
    expect(await policy.targetInvitedRequester({ targetId: 'wes', requesterEmail: 'friend@example.com' })).toBe(true);
    expect(await policy.targetInvitedRequester({ targetId: 'wes', requesterEmail: 'stranger@example.com' })).toBe(false);
    expect(await policy.targetInvitedRequester({ targetId: 'britt', requesterEmail: 'friend@example.com' })).toBe(false);
    // No plaintext address is stored
    const [doc] = [...mockDb.rows('connectionInvites').values()];
    expect(JSON.stringify(doc)).not.toMatch(/example\.com/);
  });

  test('old invites expire', async () => {
    await policy.recordEmailInvite('wes', 'friend@example.com', new Date('2026-01-01T00:00:00Z'));
    expect(await policy.hasEmailInvite('wes', 'friend@example.com', new Date('2026-02-01T00:00:00Z'))).toBe(true);
    expect(await policy.hasEmailInvite('wes', 'friend@example.com', new Date('2026-12-01T00:00:00Z'))).toBe(false);
  });

  test('nothing verifies without a token or an invite (the bare autoAccept case)', async () => {
    expect(await policy.targetInvitedRequester({ targetId: 'wes', requesterEmail: 'sal@example.com', inviteToken: undefined })).toBe(false);
  });
});

describe('request notification cooldown', () => {
  test('one notification per pair per 24 hours', async () => {
    const t0 = new Date('2026-10-01T12:00:00Z');
    expect(await policy.claimRequestNotification('sal', 'wes', t0)).toBe(true);
    // request → decline → request again an hour later: no second email/push
    expect(await policy.claimRequestNotification('sal', 'wes', new Date('2026-10-01T13:00:00Z'))).toBe(false);
    // other pairs are independent
    expect(await policy.claimRequestNotification('sal', 'britt', new Date('2026-10-01T13:00:00Z'))).toBe(true);
    expect(await policy.claimRequestNotification('wes', 'sal', new Date('2026-10-01T13:00:00Z'))).toBe(true);
    // after the window it may notify again
    expect(await policy.claimRequestNotification('sal', 'wes', new Date('2026-10-02T12:00:01Z'))).toBe(true);
    expect(mockDb.rows('connectionRequestLog').get('sal_wes')).toMatchObject({ notifyCount: 2 });
  });
});
