// What the number on the app icon means. The rule: it counts things WAITING for
// you that you can open. A push that leaves nothing behind gets no badge, so
// the icon never points at a screen that doesn't exist.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { shouldBadge, computeBadgeCount, BADGE_WORTHY } = require('../badgeService');

const put = (col, id, data) => mockDb.rows(col).set(id, data);
beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
});

describe('which pushes badge', () => {
  test('things that land somewhere you can open', () => {
    expect(shouldBadge('new_message')).toBe(true);
    expect(shouldBadge('connection_request')).toBe(true);
    expect(shouldBadge('place_comment')).toBe(true);
    expect(shouldBadge('moment_tag')).toBe(true);
  });

  // The bug this whole change exists for: "someone added a place" is a banner,
  // never written to the Notifications list, so a badge for it pointed at
  // nothing and nothing cleared it.
  test('ephemeral banners do not', () => {
    expect(shouldBadge('activity_notification')).toBe(false);
    expect(shouldBadge('daily_summary')).toBe(false);
    expect(shouldBadge('engagement_reminder')).toBe(false);
  });

  // Own-order status with no tap destination — badging it would recreate the
  // same dead end.
  test('outbound postcard status does not', () => {
    expect(shouldBadge('postcard_order')).toBe(false);
  });

  // A postcard someone SENDS you arrives as a message, which does badge.
  test('an incoming postcard badges, because it is a message', () => {
    expect(shouldBadge('new_message')).toBe(true);
    expect(BADGE_WORTHY.has('new_message')).toBe(true);
  });

  test('an unknown type fails closed rather than badging', () => {
    expect(shouldBadge('something_new')).toBe(false);
    expect(shouldBadge(undefined)).toBe(false);
  });
});

describe('computeBadgeCount', () => {
  test('sums unread messages, pending requests and unread notifications', async () => {
    put('messageReads', 'm1', { userId: 'me', isRead: false });
    put('messageReads', 'm2', { userId: 'me', isRead: false });
    put('messageReads', 'm3', { userId: 'me', isRead: true });
    put('connections', 'c1', { connectedUserId: 'me', status: 'pending' });
    put('connections', 'c2', { connectedUserId: 'me', status: 'accepted' });
    put('notifications', 'n1', { userId: 'me', read: false });
    put('notifications', 'n2', { userId: 'me', read: true });

    expect(await computeBadgeCount('me')).toBe(4); // 2 messages + 1 request + 1 notification
  });

  // The gap that let a like or comment never reach the icon.
  test('unread notifications count, not just messages and requests', async () => {
    put('notifications', 'n1', { userId: 'me', read: false });
    expect(await computeBadgeCount('me')).toBe(1);
  });

  test('nothing waiting is zero, and someone else\'s items never count', async () => {
    put('messageReads', 'm1', { userId: 'someone-else', isRead: false });
    put('notifications', 'n1', { userId: 'someone-else', read: false });
    expect(await computeBadgeCount('me')).toBe(0);
  });

  test('no user id is zero rather than a crash', async () => {
    expect(await computeBadgeCount(null)).toBe(0);
  });
});
