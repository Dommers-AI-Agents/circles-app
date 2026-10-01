// Security audit 2026-10-01: the allowlists that decide what one person's
// data looks like when it is served to someone else.
const {
  publicUserSummary,
  visibleLocation,
  matchesUserSearch,
  searchRelevanceRank,
  publicCircleFields,
  isPubliclyViewableMoment,
  coarseDistanceKm
} = require('../publicProjection');

describe('publicUserSummary', () => {
  test('name and photo only — never email or phone', () => {
    const card = publicUserSummary({
      id: 'u1', displayName: 'Sal', profilePicture: 'p.jpg',
      email: 'sal@example.com', phoneNumber: '+15555550100', deviceTokens: ['t']
    });
    expect(card).toEqual({ id: 'u1', displayName: 'Sal', profilePicture: 'p.jpg' });
  });

  test('falls back to Unknown User', () => {
    expect(publicUserSummary({ id: 'u1' }).displayName).toBe('Unknown User');
  });
});

describe('visibleLocation', () => {
  test('hidden when "Show my city" is off, shown otherwise', () => {
    expect(visibleLocation({ location: 'Charlotte', preferences: { showLocation: false } })).toBeNull();
    expect(visibleLocation({ location: 'Charlotte', preferences: { showLocation: true } })).toBe('Charlotte');
    expect(visibleLocation({ location: 'Charlotte' })).toBe('Charlotte');
  });
});

describe('matchesUserSearch', () => {
  const user = {
    displayName: 'William Smith', firstName: 'William', lastName: 'Smith',
    email: 'wsecret@example.com', phoneNumber: '(704) 555-0199'
  };

  test('matches name substrings', () => {
    expect(matchesUserSearch(user, 'mith')).toBe(true);
    expect(matchesUserSearch(user, 'will')).toBe(true);
  });

  test('never matches on email or phone (no lookup oracle)', () => {
    expect(matchesUserSearch(user, 'wsecret')).toBe(false);
    expect(matchesUserSearch(user, 'example.com')).toBe(false);
    expect(matchesUserSearch(user, '5550199')).toBe(false);
    expect(matchesUserSearch(user, '704')).toBe(false);
  });

  test('empty term or user matches nothing', () => {
    expect(matchesUserSearch(user, '')).toBe(false);
    expect(matchesUserSearch(null, 'will')).toBe(false);
  });
});

describe('searchRelevanceRank', () => {
  test('exact < prefix < word prefix < substring', () => {
    expect(searchRelevanceRank({ displayName: 'Sal' }, 'sal')).toBe(0);
    expect(searchRelevanceRank({ displayName: 'Sally' }, 'sal')).toBe(1);
    expect(searchRelevanceRank({ displayName: 'Ann Salter' }, 'sal')).toBe(2);
    expect(searchRelevanceRank({ displayName: 'Rosalind' }, 'sal')).toBe(3);
  });
});

describe('publicCircleFields', () => {
  test('drops guest lists, editors, followers, likes and the place id list', () => {
    const out = publicCircleFields({
      _id: 'c1', id: 'c1', name: 'Tacos', owner: 'u1', privacy: 'public', category: 'food',
      createdAt: '2026-01-01', updatedAt: '2026-01-02', placesCount: 3,
      sharedWith: ['invitee@example.com'], editors: ['u2'], followers: ['u3'],
      likes: ['u4'], places: ['p1'], shareSettings: { x: 1 }, activeShares: ['s1']
    });
    expect(out).toEqual({
      _id: 'c1', id: 'c1', name: 'Tacos', owner: 'u1', privacy: 'public', category: 'food',
      createdAt: '2026-01-01', updatedAt: '2026-01-02', placesCount: 3
    });
  });
});

describe('isPubliclyViewableMoment', () => {
  const base = { visibility: 'public', uploadStatus: 'ready', deletedAt: null };

  test('public, live, un-moderated → viewable', () => {
    expect(isPubliclyViewableMoment(base)).toBe(true);
  });

  test.each([
    ['private', { visibility: 'private' }],
    ['network', { visibility: 'network' }],
    ['followers', { visibility: 'followers' }],
    ['inner circle', { visibility: 'innerCircle' }],
    ['no visibility at all', { visibility: undefined }],
    ['under review', { moderationStatus: 'under_review' }],
    ['removed', { moderationStatus: 'removed' }],
    ['deleted', { deletedAt: '2026-09-01' }],
    ['still uploading', { uploadStatus: 'pending' }]
  ])('%s → not viewable', (_label, over) => {
    expect(isPubliclyViewableMoment({ ...base, ...over })).toBe(false);
  });

  test('missing moment → not viewable', () => {
    expect(isPubliclyViewableMoment(null)).toBe(false);
  });
});

describe('coarseDistanceKm', () => {
  test.each([
    [0, 0.5], [0.04, 0.5], [0.99, 0.5],
    [1, 5], [4.2, 5], [5, 5],
    [5.1, 25], [24.9, 25], [25, 25],
    [25.1, 100], [150, 100]
  ])('%p km → %p', (km, bucket) => {
    expect(coarseDistanceKm(km)).toBe(bucket);
  });

  test('anything under 1 km stays under 1 (the app labels it "Near you")', () => {
    expect(coarseDistanceKm(0.3)).toBeLessThan(1);
  });

  test('garbage → null', () => {
    expect(coarseDistanceKm(NaN)).toBeNull();
    expect(coarseDistanceKm(-1)).toBeNull();
    expect(coarseDistanceKm(undefined)).toBeNull();
  });
});
