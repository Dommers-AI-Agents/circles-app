const {
  PRIVACY,
  FOLLOW_CIRCLE,
  normalizePrivacy,
  toMomentPrivacy,
  canViewAtTier,
  canViewCircle,
  isPlaceVisibleToViewer,
  canViewMoment
} = require('../visibility');

// A context describes ONE viewer's relationships, keyed by the other person's
// id. Everything below is written from the point of view of someone looking at
// content owned by "owner", so each role gets its own context.
const contextFor = (role) => ({
  connections: new Set(role === 'connection' || role === 'insider' ? ['owner'] : []),
  following: new Set(role === 'follower' ? ['owner'] : []),
  // Only the insider is on the owner's Inner Circle list.
  innerCircleGrantors: new Set(role === 'insider' ? ['owner'] : [])
});

const ctx = contextFor;
const strangerCtx = () => contextFor('stranger');

describe('normalizePrivacy', () => {
  test('every spelling we have ever stored lands on the ladder', () => {
    expect(normalizePrivacy('public')).toBe(PRIVACY.PUBLIC);
    expect(normalizePrivacy('myNetwork')).toBe(PRIVACY.CONNECTIONS);
    expect(normalizePrivacy('my_network')).toBe(PRIVACY.CONNECTIONS);
    expect(normalizePrivacy('network')).toBe(PRIVACY.CONNECTIONS);
    expect(normalizePrivacy('friends')).toBe(PRIVACY.CONNECTIONS);
    expect(normalizePrivacy('innerCircle')).toBe(PRIVACY.INNER_CIRCLE);
    expect(normalizePrivacy('private')).toBe(PRIVACY.PRIVATE);
    expect(normalizePrivacy('followCircle')).toBe(FOLLOW_CIRCLE);
  });

  test('anything we do not recognise is null, never a tier', () => {
    expect(normalizePrivacy('restricted')).toBeNull();
    expect(normalizePrivacy(undefined)).toBeNull();
    expect(normalizePrivacy(null)).toBeNull();
    expect(normalizePrivacy('')).toBeNull();
    expect(normalizePrivacy(3)).toBeNull();
  });

  test('moments keep their own spelling on the way back out', () => {
    expect(toMomentPrivacy('myNetwork')).toBe('network');
    expect(toMomentPrivacy('network')).toBe('network');
    expect(toMomentPrivacy('innerCircle')).toBe(PRIVACY.INNER_CIRCLE);
    expect(toMomentPrivacy('public')).toBe(PRIVACY.PUBLIC);
  });
});

describe('canViewAtTier', () => {
  test('the owner sees their own content at every tier', () => {
    for (const tier of ['public', 'followers', 'myNetwork', 'innerCircle', 'private']) {
      expect(canViewAtTier('owner', tier, 'owner', strangerCtx())).toBe(true);
    }
  });

  test('public reaches everyone, private reaches no one', () => {
    expect(canViewAtTier('owner', 'public', 'stranger', strangerCtx())).toBe(true);
    expect(canViewAtTier('owner', 'private', 'connection', ctx('connection'))).toBe(false);
    expect(canViewAtTier('owner', 'private', 'insider', ctx('insider'))).toBe(false);
  });

  test('connections tier admits connections and nobody else', () => {
    expect(canViewAtTier('owner', 'myNetwork', 'connection', ctx('connection'))).toBe(true);
    expect(canViewAtTier('owner', 'myNetwork', 'follower', ctx('follower'))).toBe(false);
    expect(canViewAtTier('owner', 'myNetwork', 'stranger', ctx())).toBe(false);
  });

  // The whole point of the tier: a connection you did not pick stays out.
  test('inner circle admits only the people on the list', () => {
    expect(canViewAtTier('owner', 'innerCircle', 'insider', ctx('insider'))).toBe(true);
    expect(canViewAtTier('owner', 'innerCircle', 'connection', ctx('connection'))).toBe(false);
    expect(canViewAtTier('owner', 'innerCircle', 'stranger', strangerCtx())).toBe(false);
  });

  test('a connection clears the followers bar without following', () => {
    expect(canViewAtTier('owner', 'followers', 'follower', ctx('follower'))).toBe(true);
    expect(canViewAtTier('owner', 'followers', 'connection', ctx('connection'))).toBe(true);
    expect(canViewAtTier('owner', 'followers', 'stranger', strangerCtx())).toBe(false);
  });

  test('an unknown tier denies rather than falling through to public', () => {
    expect(canViewAtTier('owner', 'restricted', 'connection', ctx('connection'))).toBe(false);
    expect(canViewAtTier('owner', undefined, 'connection', ctx('connection'))).toBe(false);
  });

  test('a missing context denies every tier above public', () => {
    expect(canViewAtTier('owner', 'public', 'stranger', undefined)).toBe(true);
    expect(canViewAtTier('owner', 'innerCircle', 'insider', undefined)).toBe(false);
    expect(canViewAtTier('owner', 'myNetwork', 'connection', undefined)).toBe(false);
  });
});

describe('canViewCircle', () => {
  const circle = (privacy, sharedWith = []) => ({ owner: 'owner', privacy, sharedWith });

  test('the guest list grants access at any tier, including private', () => {
    expect(canViewCircle(circle('private', ['guest']), 'guest', strangerCtx())).toBe(true);
    expect(canViewCircle(circle('innerCircle', ['guest']), 'guest', strangerCtx())).toBe(true);
    expect(canViewCircle(circle('private', []), 'guest', strangerCtx())).toBe(false);
  });

  test('inner circle circles are hidden from ordinary connections', () => {
    expect(canViewCircle(circle('innerCircle'), 'insider', ctx('insider'))).toBe(true);
    expect(canViewCircle(circle('innerCircle'), 'connection', ctx('connection'))).toBe(false);
  });

  test('a missing circle is not visible', () => {
    expect(canViewCircle(null, 'owner', ctx('insider'))).toBe(false);
  });
});

describe('isPlaceVisibleToViewer', () => {
  const place = (privacy) => ({ addedBy: 'owner', privacy });

  test('the person who saved it always sees it', () => {
    expect(isPlaceVisibleToViewer(place('private'), 'owner', strangerCtx())).toBe(true);
  });

  test('followCircle and a missing value defer to the circle', () => {
    expect(isPlaceVisibleToViewer(place('followCircle'), 'stranger', strangerCtx())).toBe(true);
    expect(isPlaceVisibleToViewer(place(undefined), 'stranger', strangerCtx())).toBe(true);
    expect(isPlaceVisibleToViewer(place(null), 'stranger', strangerCtx())).toBe(true);
  });

  // "No privacy field" means inherit the circle; "a value we don't recognise"
  // does not, and must not be collapsed into it.
  test('an unrecognised value denies rather than inheriting', () => {
    expect(isPlaceVisibleToViewer(place('restricted'), 'stranger', strangerCtx())).toBe(false);
    expect(isPlaceVisibleToViewer(place('restricted'), 'connection', ctx('connection'))).toBe(false);
    expect(isPlaceVisibleToViewer(place('restricted'), 'owner', strangerCtx())).toBe(true);
  });

  test('a private place stays hidden inside a circle the viewer can see', () => {
    expect(isPlaceVisibleToViewer(place('private'), 'connection', ctx('connection'))).toBe(false);
  });

  // Previously any non-private value inherited the circle, so a place marked
  // Connections inside a public circle was served to strangers.
  test('a place narrows its circle rather than inheriting it', () => {
    expect(isPlaceVisibleToViewer(place('myNetwork'), 'connection', ctx('connection'))).toBe(true);
    expect(isPlaceVisibleToViewer(place('myNetwork'), 'stranger', strangerCtx())).toBe(false);
    expect(isPlaceVisibleToViewer(place('innerCircle'), 'insider', ctx('insider'))).toBe(true);
    expect(isPlaceVisibleToViewer(place('innerCircle'), 'connection', ctx('connection'))).toBe(false);
  });
});

describe('canViewMoment', () => {
  const moment = (visibility) => ({ userId: 'owner', visibility });

  test('the moment vocabulary maps onto the same ladder', () => {
    expect(canViewMoment(moment('network'), 'connection', ctx('connection'))).toBe(true);
    expect(canViewMoment(moment('network'), 'follower', ctx('follower'))).toBe(false);
    expect(canViewMoment(moment('followers'), 'follower', ctx('follower'))).toBe(true);
    expect(canViewMoment(moment('innerCircle'), 'insider', ctx('insider'))).toBe(true);
    expect(canViewMoment(moment('innerCircle'), 'connection', ctx('connection'))).toBe(false);
    expect(canViewMoment(moment('private'), 'insider', ctx('insider'))).toBe(false);
  });
});

// Apple sign-in writes ids as "000454.<uid>.2127" in some places and the bare
// uid in others. Every comparison here must see through that, or those accounts
// lose access to their own content.
describe('Apple-format ids', () => {
  const complex = '000454.9b5eeac93282416c9bc6dcecbc49b40f.2127';
  const simple = '9b5eeac93282416c9bc6dcecbc49b40f';

  test('the owner check sees both shapes as the same person', () => {
    expect(canViewAtTier(complex, 'private', simple, strangerCtx())).toBe(true);
    expect(canViewCircle({ owner: simple, privacy: 'private' }, complex, strangerCtx())).toBe(true);
    expect(isPlaceVisibleToViewer({ addedBy: complex, privacy: 'private' }, simple, strangerCtx())).toBe(true);
  });

  test('a guest list entry matches across shapes', () => {
    const circle = { owner: 'someone', privacy: 'private', sharedWith: [complex] };
    expect(canViewCircle(circle, simple, strangerCtx())).toBe(true);
  });

  test('tier lookups match a normalised relationship set', () => {
    const ctxWithComplexOwner = {
      connections: new Set([simple]),
      following: new Set(),
      innerCircleGrantors: new Set([simple])
    };
    expect(canViewAtTier(complex, 'myNetwork', 'viewer', ctxWithComplexOwner)).toBe(true);
    expect(canViewAtTier(complex, 'innerCircle', 'viewer', ctxWithComplexOwner)).toBe(true);
  });
});
