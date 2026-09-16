const { appendRating } = require('../ratingHistory');

describe('appendRating', () => {
  it('starts a history from the first rating', () => {
    expect(appendRating(null, { rating: 7, at: '2026-09-01T00:00:00.000Z' }))
      .toEqual([{ rating: 7, at: '2026-09-01T00:00:00.000Z' }]);
  });
  it('appends a changed score, oldest first', () => {
    const h = appendRating([{ rating: 7, at: 'a' }], { rating: 9, at: 'b' });
    expect(h.map((e) => e.rating)).toEqual([7, 9]);
  });
  it('ignores a repeat of the current score with no check-in', () => {
    expect(appendRating([{ rating: 7, at: 'a' }], { rating: 7, at: 'b' })).toBeNull();
  });
  it('records a repeat score when a check-in prompted it', () => {
    const h = appendRating([{ rating: 7, at: 'a' }], { rating: 7, at: 'b', checkInId: 'c1' });
    expect(h).toEqual([{ rating: 7, at: 'a' }, { rating: 7, at: 'b', checkInId: 'c1' }]);
  });
  it('never appends a cleared or junk rating, and clamps/rounds', () => {
    expect(appendRating([], { rating: null })).toBeNull();
    expect(appendRating([], { rating: 'x' })).toBeNull();
    expect(appendRating([], { rating: 12.6, at: 'a' })).toEqual([{ rating: 10, at: 'a' }]);
    expect(appendRating([], { rating: -3, at: 'a' })).toEqual([{ rating: 0, at: 'a' }]);
  });
  it('seeds a pre-history save with its existing rating so the trend survives', () => {
    const h = appendRating(undefined, { rating: 9, at: 'b' }, { rating: 7, at: 'a' });
    expect(h).toEqual([{ rating: 7, at: 'a' }, { rating: 9, at: 'b' }]);
    // same score as the seed with no check-in: seed only, no duplicate
    expect(appendRating([], { rating: 7, at: 'b' }, { rating: 7, at: 'a' })).toBeNull();
    // seed is ignored once a history exists
    expect(appendRating([{ rating: 5, at: 'x' }], { rating: 6, at: 'y' }, { rating: 7, at: 'a' }).map((e) => e.rating)).toEqual([5, 6]);
  });

  it('does not mutate the input array', () => {
    const input = [{ rating: 5, at: 'a' }];
    appendRating(input, { rating: 6, at: 'b' });
    expect(input.length).toBe(1);
  });
});
