const { isCheckInVisibleTo, isPrivateCheckIn } = require('../checkInVisibility');

const base = {
  userId: 'owner',
  notifiedUsers: [],
  notifiedGroups: [],
  showInActivityFeed: true,
};

const ctx = (overrides = {}) => ({
  connectionIds: new Set(['owner', 'friend']),
  innerCircleGrantors: new Set(['owner']),
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

// An Inner Circle check-in stops at the owner's list. The feed flag is about
// where it appears, not who may see it, so turning it on must not widen the
// audience — that is the mistake the tier exists to prevent.
describe('inner circle check-ins', () => {
  const inner = { ...base, audience: 'innerCircle', showInActivityFeed: true };

  test('only people on the list see it, feed flag notwithstanding', async () => {
    expect(await isCheckInVisibleTo(inner, 'insider', ctx())).toBe(true);
    expect(await isCheckInVisibleTo(inner, 'friend', ctx({ innerCircleGrantors: new Set() }))).toBe(false);
  });

  test('a connection who is not on the list is out, even on the feed', async () => {
    const notListed = ctx({ innerCircleGrantors: new Set() });
    expect(await isCheckInVisibleTo(inner, 'friend', notListed)).toBe(false);
    expect(await isCheckInVisibleTo({ ...base, showInActivityFeed: true }, 'friend', notListed)).toBe(true);
  });

  test('someone it was sent to directly still sees it', async () => {
    const sent = { ...inner, notifiedUsers: ['outsider'] };
    expect(await isCheckInVisibleTo(sent, 'outsider', ctx({ innerCircleGrantors: new Set() }))).toBe(true);
  });

  test('the owner always sees their own', async () => {
    expect(await isCheckInVisibleTo(inner, 'owner', ctx({ innerCircleGrantors: new Set() }))).toBe(true);
  });
});

describe('a named Inner Circle list', () => {
  const onFamily = { userId: 'owner', audience: 'innerCircle', audienceListId: 'family', showInActivityFeed: true };
  const ctx = (listIds) => ({
    connectionIds: new Set(['owner']),
    innerCircleGrantors: new Set(['owner']),
    innerCircleLists: new Map([['owner', new Set(listIds)]])
  });

  it('reaches the list it named, and no other list of the same owner', async () => {
    expect(await isCheckInVisibleTo(onFamily, 'viewer', ctx(['family']))).toBe(true);
    expect(await isCheckInVisibleTo(onFamily, 'viewer', ctx(['gym']))).toBe(false);
  });

  it('is invisible when the caller forgot the per-list map, rather than falling back to any list', async () => {
    const careless = { connectionIds: new Set(['owner']), innerCircleGrantors: new Set(['owner']) };
    expect(await isCheckInVisibleTo(onFamily, 'viewer', careless)).toBe(false);
  });

  it('still reaches anyone it was sent to directly', async () => {
    const sent = { ...onFamily, notifiedUsers: ['viewer'] };
    expect(await isCheckInVisibleTo(sent, 'viewer', ctx(['gym']))).toBe(true);
  });

  it('written before lists existed, it means any of them', async () => {
    const old = { userId: 'owner', audience: 'innerCircle', showInActivityFeed: true };
    expect(await isCheckInVisibleTo(old, 'viewer', ctx(['gym']))).toBe(true);
    expect(await isCheckInVisibleTo(old, 'viewer', { connectionIds: new Set(['owner']), innerCircleGrantors: new Set() })).toBe(false);
  });
});

describe('context shapes', () => {
  test('accepts the viewerContext `connections` set as well as the legacy `connectionIds`', async () => {
    const legacy = { connectionIds: new Set(['owner']), innerCircleGrantors: new Set(), isInAnyGroup: async () => false };
    const modern = { connections: new Set(['owner']), innerCircleGrantors: new Set(), isInAnyGroup: async () => false };
    const stranger = { connections: new Set(), innerCircleGrantors: new Set(), isInAnyGroup: async () => false };
    expect(await isCheckInVisibleTo(base, 'friend', legacy)).toBe(true);
    expect(await isCheckInVisibleTo(base, 'friend', modern)).toBe(true);
    expect(await isCheckInVisibleTo(base, 'friend', stranger)).toBe(false);
  });
});
