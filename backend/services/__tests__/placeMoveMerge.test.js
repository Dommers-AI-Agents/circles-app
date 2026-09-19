const { sameVenue, carryOverPatch } = require('../placeMoveMerge');

describe('sameVenue', () => {
  test('canonical id wins, then google id, then name+address', () => {
    expect(sameVenue({ globalPlaceId: 'g1' }, { globalPlaceId: 'g1', googlePlaceId: 'x' })).toBe(true);
    expect(sameVenue({ globalPlaceId: 'g1' }, { globalPlaceId: 'g2' })).toBe(false);
    expect(sameVenue({ googlePlaceId: 'p1' }, { googlePlaceId: 'p1' })).toBe(true);
    expect(sameVenue({ name: 'The Elbow Room', address: '416 Main St' }, { name: 'the elbow room ', address: '416 main st' })).toBe(true);
    expect(sameVenue({ name: 'A', address: '1' }, { name: 'A', address: '2' })).toBe(false);
    expect(sameVenue({}, {})).toBe(false);
  });
});

describe('carryOverPatch', () => {
  test('fills blanks on the staying copy, never overwrites', () => {
    const source = { privateNotes: 'great wings', publicNotes: '', tags: ['wings', 'bar'], photos: ['a.jpg'], userRating: 8 };
    const target = { privateNotes: '', publicNotes: 'nice patio', tags: ['bar'], photos: ['b.jpg', 'a.jpg'], userRating: 6 };
    expect(carryOverPatch(source, target)).toEqual({ privateNotes: 'great wings', tags: ['bar', 'wings'] });
  });

  test('nothing to carry → empty patch; photos union keeps uploads', () => {
    expect(carryOverPatch({ privateNotes: '' }, { privateNotes: '' })).toEqual({});
    expect(carryOverPatch({ photos: [{ url: 'x' }, { url: 'y' }] }, { photos: [{ url: 'x' }] })).toEqual({ photos: [{ url: 'x' }, { url: 'y' }] });
  });
});
