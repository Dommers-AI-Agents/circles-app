const { isCheckInVisibleTo, isPrivateCheckIn } = require('../checkInVisibility');

const base = {
  userId: 'owner',
  notifiedUsers: [],
  notifiedGroups: [],
  showInActivityFeed: true,
};

const ctx = (overrides = {}) => ({
  connectionIds: new Set(['owner', 'friend']),
  isInAnyGroup: async () => false,
  ...overrides,
});

describe('check-in visibility', () => {
  test('the owner always sees their own check-in, private or not', async () => {
    expect(await isCheckInVisibleTo(base, 'owner', ctx())).toBe(true);
    expect(await isCheckInVisibleTo({ ...base, isPrivate: true, showInActivityFeed: false }, 'owner', ctx())).toBe(true);
  });

  test('a private check-in is invisible to everyone else, even someone listed', async () => {
    const priv = { ...base, isPrivate: true, notifiedUsers: ['friend'], showInActivityFeed: true };
    expect(isPrivateCheckIn(priv)).toBe(true);
    expect(await isCheckInVisibleTo(priv, 'friend', ctx())).toBe(false);
    expect(await isCheckInVisibleTo(priv, 'friend', ctx({ isInAnyGroup: async () => true }))).toBe(false);
  });

  test('notified people see it regardless of the feed flag or connection', async () => {
    const quiet = { ...base, showInActivityFeed: false, notifiedUsers: ['stranger'] };
    expect(await isCheckInVisibleTo(quiet, 'stranger', ctx())).toBe(true);
    expect(await isCheckInVisibleTo(quiet, 'friend', ctx())).toBe(false);
  });

  test('connections see feed check-ins only', async () => {
    expect(await isCheckInVisibleTo(base, 'friend', ctx())).toBe(true);
    expect(await isCheckInVisibleTo({ ...base, showInActivityFeed: false }, 'friend', ctx())).toBe(false);
    // A stranger's own connection set doesn't contain the owner
    expect(await isCheckInVisibleTo(base, 'stranger', ctx({ connectionIds: new Set(['stranger']) }))).toBe(false);
  });

  test('group members see it through the group', async () => {
    const grouped = { ...base, showInActivityFeed: false, notifiedGroups: ['g1'] };
    const inGroup = ctx({ isInAnyGroup: async (viewer, groups) => viewer === 'member' && groups.includes('g1') });
    expect(await isCheckInVisibleTo(grouped, 'member', inGroup)).toBe(true);
    expect(await isCheckInVisibleTo(grouped, 'stranger', inGroup)).toBe(false);
  });

  test('legacy docs without the new field are treated as not private', async () => {
    const legacy = { userId: 'owner', notifiedUsers: ['friend'] };
    expect(isPrivateCheckIn(legacy)).toBe(false);
    expect(await isCheckInVisibleTo(legacy, 'friend', ctx())).toBe(true);
  });
});
