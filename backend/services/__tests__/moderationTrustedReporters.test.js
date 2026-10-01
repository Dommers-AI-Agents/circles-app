// Security audit 2026-10-01: auto-hide counts only trusted reporters
// (account ≥ 7 days old, not banned), so two throwaway accounts can't hide
// anyone's content. Every report still alerts the admin.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/adminAlerts', () => ({ alertAdmin: jest.fn(async () => true) }));

const {
  AUTO_HIDE_THRESHOLD,
  isTrustedReporter,
  applyAutoHideIfNeeded,
  notifyAdmin
} = require('../moderationService');
const { alertAdmin } = require('../adminAlerts');

const DAY = 24 * 60 * 60 * 1000;
const daysAgo = (n) => new Date(Date.now() - n * DAY).toISOString();
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const snap = (data, extra = {}) => ({ exists: data !== undefined, data: () => data, ...extra });

const report = (reporterId) => put('reports', `comment_c1_${reporterId}`, {
  reporterId, reportedItemType: 'comment', reportedItemId: 'c1', reason: 'spam'
});

beforeEach(() => {
  for (const name of ['users', 'reports', 'placeComments']) mockDb.rows(name).clear();
  jest.clearAllMocks();
});

describe('isTrustedReporter', () => {
  test('a week-old, unbanned account is trusted', () => {
    expect(isTrustedReporter(snap({ createdAt: daysAgo(8) }))).toBe(true);
  });
  test('a brand-new account is not', () => {
    expect(isTrustedReporter(snap({ createdAt: daysAgo(1) }))).toBe(false);
  });
  test('a banned account is not, however old', () => {
    expect(isTrustedReporter(snap({ createdAt: daysAgo(400), banned: true }))).toBe(false);
  });
  test('a missing account is not', () => {
    expect(isTrustedReporter(snap(undefined))).toBe(false);
  });
  test('Firestore Timestamp createdAt and doc createTime both work', () => {
    const ts = (ms) => ({ toMillis: () => ms });
    expect(isTrustedReporter(snap({ createdAt: ts(Date.now() - 30 * DAY) }))).toBe(true);
    expect(isTrustedReporter(snap({}, { createTime: ts(Date.now() - DAY) }))).toBe(false);
    expect(isTrustedReporter(snap({}, { createTime: ts(Date.now() - 30 * DAY) }))).toBe(true);
  });
  test('legacy account with no age at all is trusted (nobody can mint one now)', () => {
    expect(isTrustedReporter(snap({}))).toBe(true);
  });
});

describe('applyAutoHideIfNeeded', () => {
  beforeEach(async () => {
    await put('placeComments', 'c1', { text: 'hello', moderationStatus: 'visible' });
  });

  test('threshold is unchanged', () => {
    expect(AUTO_HIDE_THRESHOLD).toBe(2);
  });

  test('two fresh accounts cannot hide content', async () => {
    await put('users', 'sock1', { createdAt: daysAgo(0) });
    await put('users', 'sock2', { createdAt: daysAgo(1) });
    await report('sock1');
    await report('sock2');

    const result = await applyAutoHideIfNeeded('comment', 'c1');
    expect(result).toMatchObject({ hidden: false, count: 2, trustedCount: 0 });
    expect(mockDb.rows('placeComments').get('c1').moderationStatus).toBe('visible');
  });

  test('a banned reporter does not count', async () => {
    await put('users', 'old', { createdAt: daysAgo(30) });
    await put('users', 'bannedOld', { createdAt: daysAgo(30), banned: true });
    await report('old');
    await report('bannedOld');

    expect(await applyAutoHideIfNeeded('comment', 'c1')).toMatchObject({ hidden: false, trustedCount: 1 });
  });

  test('two trusted reporters still hide it', async () => {
    await put('users', 'a', { createdAt: daysAgo(30) });
    await put('users', 'b', { createdAt: daysAgo(10) });
    await put('users', 'fresh', { createdAt: daysAgo(0) });
    await report('a');
    await report('b');
    await report('fresh');

    const result = await applyAutoHideIfNeeded('comment', 'c1');
    expect(result).toMatchObject({ hidden: true, count: 3, trustedCount: 2 });
    expect(mockDb.rows('placeComments').get('c1').moderationStatus).toBe('under_review');
  });
});

describe('notifyAdmin', () => {
  test('reports from untrusted accounts still alert the admin, with the trusted count', async () => {
    await notifyAdmin(
      { id: 'r1', type: 'content', reportedItemType: 'comment', reportedItemId: 'c1', reason: 'spam', reporterId: 'sock1' },
      { autoHidden: false, reporterCount: 2, trustedCount: 0 }
    );
    expect(alertAdmin).toHaveBeenCalledTimes(1);
    expect(alertAdmin.mock.calls[0][0].body).toContain('Trusted reporters (account ≥7 days, not banned): 0');
  });
});
