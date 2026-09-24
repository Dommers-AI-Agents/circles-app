// "Who can see my activity": the account-level grid on top of every item's
// own privacy. Absent settings change nothing; a checked column a viewer
// qualifies for lets the row through; the item gates still narrow first.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const { makeViewerContext } = require('../viewerContext');
const ap = require('../activityPrivacy');

const ACTOR = 'actor';
const INSIDER = 'insider';      // connection + on the actor's list
const FRIEND = 'friend';        // connection only
const FOLLOWER = 'follower';    // follows, not connected
const STRANGER = 'stranger';

const ctxFor = (viewerId) => makeViewerContext({
  viewerId,
  connections: viewerId === INSIDER || viewerId === FRIEND ? [ACTOR] : [],
  following: viewerId === FOLLOWER ? [ACTOR] : [],
  innerCircleLists: viewerId === INSIDER ? new Map([[ACTOR, new Set(['family'])]]) : new Map()
});

const grid = (overrides) => {
  const g = ap.defaultActivityPrivacy();
  for (const [cat, row] of Object.entries(overrides)) g[cat] = { ...g[cat], ...row };
  return g;
};
const settings = (overrides) => new Map([[ACTOR, grid(overrides)]]);
const row = (type, extra = {}) => ({ id: `${type}-1`, type, actorId: ACTOR, ...extra });

beforeEach(() => mockDb.rows(COLLECTIONS.USERS).clear());

describe('the grid itself', () => {
  test('absent settings allow every audience for every category', () => {
    for (const category of ap.CATEGORIES) {
      expect(ap.allowedAudiences(undefined, category)).toEqual({ public: true, myNetwork: true, innerCircle: true });
    }
  });

  test('a missing category defaults to all three audiences', () => {
    const s = { checkIns: { public: false, myNetwork: false, innerCircle: true } };
    expect(ap.allowedAudiences(s, 'photos')).toEqual({ public: true, myNetwork: true, innerCircle: true });
    expect(ap.allowedAudiences(s, 'checkIns')).toEqual({ public: false, myNetwork: false, innerCircle: true });
  });

  test('normalize fills gaps and reads non-booleans as true', () => {
    const g = ap.normalizeActivityPrivacy({ checkIns: { public: false, myNetwork: 'no' }, junk: 1 });
    expect(g.checkIns).toEqual({ public: false, myNetwork: true, innerCircle: true });
    expect(Object.keys(g).sort()).toEqual([...ap.CATEGORIES].sort());
    expect(g.junk).toBeUndefined();
  });

  test('validate rejects an unknown category, an unknown audience, a missing audience and a non-boolean', () => {
    const full = ap.defaultActivityPrivacy();
    expect(ap.validateActivityPrivacy(full)).toEqual(full);
    expect(() => ap.validateActivityPrivacy({ ...full, extra: {} })).toThrow(expect.objectContaining({ status: 400, code: 'ACTIVITY_PRIVACY_INVALID' }));
    expect(() => ap.validateActivityPrivacy({ ...full, photos: { ...full.photos, followers: true } })).toThrow(expect.objectContaining({ code: 'ACTIVITY_PRIVACY_INVALID' }));
    expect(() => ap.validateActivityPrivacy({ ...full, photos: { public: true, myNetwork: true } })).toThrow(expect.objectContaining({ code: 'ACTIVITY_PRIVACY_INVALID' }));
    expect(() => ap.validateActivityPrivacy({ ...full, photos: { ...full.photos, public: 'yes' } })).toThrow(expect.objectContaining({ code: 'ACTIVITY_PRIVACY_INVALID' }));
    const { checkIns, ...missing } = full;
    expect(() => ap.validateActivityPrivacy(missing)).toThrow(expect.objectContaining({ code: 'ACTIVITY_PRIVACY_INVALID' }));
  });

  test('every mapped activity type resolves to a grid row; venue rows and unknown types to none', () => {
    for (const [type, category] of Object.entries(ap.ACTIVITY_CATEGORY)) {
      expect(ap.CATEGORIES).toContain(category);
      expect(ap.categoryOf({ type })).toBe(category);
    }
    expect(ap.categoryOf({ type: 'venue_offer' })).toBeNull();
    expect(ap.categoryOf({ type: 'user_followed' })).toBeNull();
  });
});

describe('who qualifies for which column', () => {
  test('self, inner-circle member, connection, follower, stranger', () => {
    expect(ap.qualifyingAudiences(ctxFor(ACTOR), ACTOR)).toBeNull();
    expect(ap.qualifyingAudiences(ctxFor(INSIDER), ACTOR)).toEqual(['public', 'myNetwork', 'innerCircle']);
    expect(ap.qualifyingAudiences(ctxFor(FRIEND), ACTOR)).toEqual(['public', 'myNetwork']);
    expect(ap.qualifyingAudiences(ctxFor(FOLLOWER), ACTOR)).toEqual(['public']);
    expect(ap.qualifyingAudiences(ctxFor(STRANGER), ACTOR)).toEqual(['public']);
  });

  test('an inner-circle member passes on myNetwork OR innerCircle — never less than an ordinary connection', () => {
    const checkIn = row('check_in');
    const onlyInner = settings({ checkIns: { public: false, myNetwork: false, innerCircle: true } });
    const onlyConnections = settings({ checkIns: { public: false, myNetwork: true, innerCircle: false } });
    expect(ap.canViewActivity(checkIn, INSIDER, ctxFor(INSIDER), onlyInner)).toBe(true);
    expect(ap.canViewActivity(checkIn, FRIEND, ctxFor(FRIEND), onlyInner)).toBe(false);
    expect(ap.canViewActivity(checkIn, FOLLOWER, ctxFor(FOLLOWER), onlyInner)).toBe(false);
    expect(ap.canViewActivity(checkIn, INSIDER, ctxFor(INSIDER), onlyConnections)).toBe(true);
    expect(ap.canViewActivity(checkIn, FRIEND, ctxFor(FRIEND), onlyConnections)).toBe(true);
  });

  test('unchecking every column means only the actor', () => {
    const nobody = settings({ photos: { public: false, myNetwork: false, innerCircle: false } });
    const photo = row('photo_uploaded');
    expect(ap.canViewActivity(photo, INSIDER, ctxFor(INSIDER), nobody)).toBe(false);
    expect(ap.canViewActivity(photo, ACTOR, ctxFor(ACTOR), nobody)).toBe(true);
  });

  test('venue actors are never gated by the grid; unknown types are item-gated only', () => {
    const offer = { id: 'o', type: 'venue_offer', actorId: 'place_abc' };
    expect(ap.canViewActivity(offer, STRANGER, ctxFor(STRANGER), new Map([['place_abc', grid({ circles: { public: false, myNetwork: false, innerCircle: false } })]]))).toBe(true);
    const legacy = row('user_followed');
    const nobody = settings({ circles: { public: false, myNetwork: false, innerCircle: false } });
    expect(ap.canViewActivity(legacy, STRANGER, ctxFor(STRANGER), nobody)).toBe(true);
  });
});

describe('item gates, moved here verbatim', () => {
  const circles = new Map([
    ['pub', { owner: ACTOR, privacy: 'public' }],
    ['net', { owner: ACTOR, privacy: 'myNetwork' }],
    ['inner', { owner: ACTOR, privacy: 'innerCircle', audienceListId: 'family' }]
  ]);

  test('filter keeps a row only when both the item gate and the grid pass', () => {
    const rows = [row('place_added', { circleId: 'net' })];
    const open = ap.filterActivitiesForViewer({ activities: rows, viewerId: FRIEND, viewerCtx: ctxFor(FRIEND), circlesById: circles, settingsByActor: new Map() });
    expect(open).toHaveLength(1);
    // Item gate fails: a follower can't see a connections circle even with the grid wide open.
    expect(ap.filterActivitiesForViewer({ activities: rows, viewerId: FOLLOWER, viewerCtx: ctxFor(FOLLOWER), circlesById: circles, settingsByActor: new Map() })).toHaveLength(0);
    // Grid fails: the circle is public, but saved places are Inner Circle only.
    const pubRows = [row('place_added', { circleId: 'pub' })];
    const tight = settings({ savedPlaces: { public: false, myNetwork: false, innerCircle: true } });
    expect(ap.filterActivitiesForViewer({ activities: pubRows, viewerId: FRIEND, viewerCtx: ctxFor(FRIEND), circlesById: circles, settingsByActor: tight })).toHaveLength(0);
    expect(ap.filterActivitiesForViewer({ activities: pubRows, viewerId: INSIDER, viewerCtx: ctxFor(INSIDER), circlesById: circles, settingsByActor: tight })).toHaveLength(1);
  });

  test('a check-in naming a list is shown only to viewers on that list', () => {
    const named = row('check_in', { metadata: { checkInAudience: 'innerCircle', audienceListId: 'family' } });
    const other = row('check_in', { metadata: { checkInAudience: 'innerCircle', audienceListId: 'work' } });
    expect(ap.passesItemGates(named, INSIDER, ctxFor(INSIDER), circles)).toBe(true);
    expect(ap.passesItemGates(other, INSIDER, ctxFor(INSIDER), circles)).toBe(false);
    expect(ap.passesItemGates(named, FRIEND, ctxFor(FRIEND), circles)).toBe(false);
  });

  test('a check-in with no list is shown to any grantor, and a plain one to anyone the circle admits', () => {
    const any = row('check_in', { metadata: { checkInAudience: 'innerCircle' } });
    expect(ap.passesItemGates(any, INSIDER, ctxFor(INSIDER), circles)).toBe(true);
    expect(ap.passesItemGates(any, FRIEND, ctxFor(FRIEND), circles)).toBe(false);
    const plain = row('check_in', { circleId: 'pub', metadata: {} });
    expect(ap.passesItemGates(plain, FOLLOWER, ctxFor(FOLLOWER), circles)).toBe(true);
  });

  test('a place row honours placePrivacy and its list', () => {
    const privatePlace = row('place_added', { circleId: 'pub', metadata: { placePrivacy: 'private' } });
    expect(ap.passesItemGates(privatePlace, FRIEND, ctxFor(FRIEND), circles)).toBe(false);
    expect(ap.passesItemGates(privatePlace, ACTOR, ctxFor(ACTOR), circles)).toBe(true);
    const listed = row('place_added', { circleId: 'pub', metadata: { placePrivacy: 'innerCircle', placeAudienceListId: 'family' } });
    expect(ap.passesItemGates(listed, INSIDER, ctxFor(INSIDER), circles)).toBe(true);
    expect(ap.passesItemGates(listed, FRIEND, ctxFor(FRIEND), circles)).toBe(false);
  });

  test('moments are judged by the relationship to the moment owner; legacy rows fall through', () => {
    const inner = row('video_liked', { actorId: FRIEND, metadata: { momentVisibility: 'innerCircle', momentOwnerId: ACTOR } });
    expect(ap.passesItemGates(inner, INSIDER, ctxFor(INSIDER), circles)).toBe(true);
    expect(ap.passesItemGates(inner, FOLLOWER, ctxFor(FOLLOWER), circles)).toBe(false);
    expect(ap.passesItemGates(row('video_uploaded'), STRANGER, ctxFor(STRANGER), circles)).toBe(true);
  });

  test('a row referencing a circle the caller did not load is withheld, not guessed', () => {
    expect(ap.passesItemGates(row('place_added', { circleId: 'missing' }), FRIEND, ctxFor(FRIEND), circles)).toBe(false);
    expect(ap.passesItemGates(row('place_added', { circleId: 'pub' }), FRIEND, ctxFor(FRIEND), null)).toBe(false);
  });
});

describe('loading grids', () => {
  test('activityPrivacyFromUserDocs reads the grid off raw docs and skips users without one', () => {
    const m = ap.activityPrivacyFromUserDocs({ a: { activityPrivacy: { photos: { public: false } } }, b: { displayName: 'x' }, c: null });
    expect(m.get('a').photos).toEqual({ public: false, myNetwork: true, innerCircle: true });
    expect(m.has('b')).toBe(false);
  });

  test('loadActivityPrivacyByActor skips venue actors and seeded ids and reads the rest in one getAll', async () => {
    await mockDb.collection(COLLECTIONS.USERS).doc('u1').set({ activityPrivacy: { checkIns: { public: false } } });
    await mockDb.collection(COLLECTIONS.USERS).doc('u2').set({ displayName: 'no grid' });
    const spy = jest.spyOn(mockDb, 'getAll');
    const seed = new Map([['u3', ap.defaultActivityPrivacy()]]);
    const m = await ap.loadActivityPrivacyByActor(['u1', 'u2', 'u3', 'place_x', 'u1'], { seed });
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0].filter((a) => a && a.id).map((a) => a.id)).toEqual(['u1', 'u2']);
    expect(m.get('u1').checkIns.public).toBe(false);
    expect(m.has('u2')).toBe(false);
    expect(m.has('u3')).toBe(true);
    spy.mockRestore();
  });
});

describe('fan-out (write time)', () => {
  test('public or connections checked → every connection; inner only → the list; nothing → nobody', () => {
    expect(ap.fanOutAllows(undefined, 'savedPlaces', [])('anyone')).toBe(true);
    const inner = grid({ savedPlaces: { public: false, myNetwork: false, innerCircle: true } });
    const allows = ap.fanOutAllows(inner, 'savedPlaces', [INSIDER]);
    expect(allows(INSIDER)).toBe(true);
    expect(allows(FRIEND)).toBe(false);
    const nobody = grid({ savedPlaces: { public: false, myNetwork: false, innerCircle: false } });
    expect(ap.fanOutAllows(nobody, 'savedPlaces', [INSIDER])(INSIDER)).toBe(false);
  });
});
