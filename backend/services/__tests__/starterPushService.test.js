jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: {} }));
const { starterPushFor } = require('../starterPushService');
const { growCopy, listNames, firstName } = require('../starterGrow');

describe('first-week pushes', () => {
  test('day 1 only when they have no place yet', () => {
    expect(starterPushFor(1, { realPlaces: 0 })).toMatchObject({ key: 'starter_push_map', type: 'starter_map' });
    expect(starterPushFor(1, { realPlaces: 1 })).toBeNull();
  });

  test('days 2 and 5 grow the map and open Discover', () => {
    const picks = { places: ['RA Sushi', 'Fellini Cucina'], placeCount: 5, people: ['Sunil Nat'], peopleCount: 1 };
    const day2 = starterPushFor(2, { realPlaces: 1, followingOthers: 0 }, picks);
    expect(day2).toMatchObject({ key: 'starter_push_grow_2', type: 'starter_follow', title: 'Places and people near you 👀' });
    expect(day2.body).toBe('People near you love RA Sushi, Fellini Cucina and 3 more. And Sunil is worth a follow.');
    const day5 = starterPushFor(5, { realPlaces: 2, followingOthers: 0 }, picks);
    expect(day5).toMatchObject({ key: 'starter_push_grow_5', title: 'Your map has 2 places — grow it' });
  });

  test('a grow push with nothing to name falls back to the generic copy', () => {
    expect(starterPushFor(2, { followingOthers: 0 }, null).body).toMatch(/Follow a few people/);
    expect(starterPushFor(5, { realPlaces: 1 }, { places: [], people: [] }).body).toMatch(/1 place\./);
  });

  test('a grown map that already follows people gets no grow push', () => {
    expect(starterPushFor(2, { realPlaces: 5, followingOthers: 3 }, {})).toBeNull();
    expect(starterPushFor(5, { realPlaces: 6, followingOthers: 4 }, {})).toBeNull();
    // Still nudged when only one half is done
    expect(starterPushFor(5, { realPlaces: 6, followingOthers: 0 }, {})).not.toBeNull();
  });

  test('other days are quiet', () => {
    for (const d of [0, 3, 4, 6, 7]) expect(starterPushFor(d, {})).toBeNull();
  });
});

describe('grow copy', () => {
  test('lists at most two names and counts the rest', () => {
    expect(listNames(['A'], 1)).toBe('A');
    expect(listNames(['A', 'B'], 2)).toBe('A and B');
    expect(listNames(['A', 'B'], 4)).toBe('A, B and 2 more');
    expect(listNames([], 0)).toBe('');
  });

  test('people go by first name and agree in number', () => {
    expect(firstName('  Jamie Rivera ')).toBe('Jamie');
    expect(growCopy({ people: ['Jamie Rivera', 'Sal Sgroi'], peopleCount: 2 }))
      .toBe('Jamie and Sal are worth a follow: every place they love shows up on your map.');
    expect(growCopy({ people: ['Jamie'], peopleCount: 1 })).toMatch(/^Jamie is worth a follow/);
  });

  test('places alone, and nothing at all', () => {
    expect(growCopy({ places: ['Hub'], placeCount: 1 })).toBe('People near you love Hub. Save the ones you love too.');
    expect(growCopy({ places: [], people: [] })).toBeNull();
    expect(growCopy(null)).toBeNull();
  });
});
