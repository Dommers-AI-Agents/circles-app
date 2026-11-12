const { liveActivityActorIds } = require('../sseActivityActors');

describe('liveActivityActorIds', () => {
  test('self plus connections (a Set) plus follows (an array), de-duplicated as strings', () => {
    const out = liveActivityActorIds('me', new Set(['a', 123]), ['b', 'a', 'me']);
    expect(out).toEqual(['me', 'a', '123', 'b']);
  });

  test('a brand-new user with no connections still hears the people they follow', () => {
    expect(liveActivityActorIds('john', new Set(), ['wes', 'sal'])).toEqual(['john', 'wes', 'sal']);
  });

  test('missing inputs leave just the viewer', () => {
    expect(liveActivityActorIds('me', undefined, null)).toEqual(['me']);
    expect(liveActivityActorIds('me', [], [])).toEqual(['me']);
  });

  test('empty ids are dropped', () => {
    expect(liveActivityActorIds('me', new Set(['', null]), [undefined, 'x'])).toEqual(['me', 'x']);
  });
});
