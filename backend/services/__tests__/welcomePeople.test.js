// A new user's first people: whoever saves the most places near them
// (Wes, 2026-11-25: the list offered someone with nothing in Charlotte).
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));

const { rankWelcomePeople, MIN_WELCOME_PEOPLE } = require('../welcomePeople');

const person = (id, extra = {}) => ({ id, localCount: 0, placesCount: 10, sharedPlaceName: null, activeBonus: 0, ...extra });
const locals = (n) => Array.from({ length: n }, (_, i) => person(`local${i}`, { localCount: n - i }));

describe('rankWelcomePeople', () => {
  test('the most places near the user leads, whatever the size of the whole map', () => {
    const ranked = rankWelcomePeople([
      person('fewHere', { localCount: 3, placesCount: 400 }),
      person('manyHere', { localCount: 25, placesCount: 30 }),
      person('someHere', { localCount: 9, placesCount: 9 }),
      ...locals(MIN_WELCOME_PEOPLE).map((p) => ({ ...p, localCount: 1 }))
    ]);
    expect(ranked.slice(0, 3).map((p) => p.id)).toEqual(['manyHere', 'someHere', 'fewHere']);
    expect(ranked[0].reason).toBe('Saves places near you');
  });

  test('a big map with nothing nearby is left out once enough local people exist', () => {
    const ranked = rankWelcomePeople([person('bigElsewhere', { placesCount: 900, activeBonus: 30 }), ...locals(MIN_WELCOME_PEOPLE)]);
    expect(ranked.map((p) => p.id)).not.toContain('bigElsewhere');
    expect(ranked).toHaveLength(MIN_WELCOME_PEOPLE);
  });

  test('a town nobody has mapped is topped up with the biggest maps, never called nearby', () => {
    const ranked = rankWelcomePeople([
      person('small', { placesCount: 2 }),
      person('big', { placesCount: 300 }),
      person('onlyLocal', { localCount: 1, placesCount: 1 })
    ]);
    expect(ranked.map((p) => p.id)).toEqual(['onlyLocal', 'big', 'small']);
    expect(ranked.find((p) => p.id === 'big').reason).toBeNull();
  });

  test('the top-up stops at the minimum', () => {
    const many = Array.from({ length: 30 }, (_, i) => person(`far${i}`, { placesCount: 100 - i }));
    const ranked = rankWelcomePeople(many);
    expect(ranked).toHaveLength(MIN_WELCOME_PEOPLE);
    expect(ranked[0].id).toBe('far0');
  });

  test('someone who saved the same place is said so, and wins a tie among locals', () => {
    const ranked = rankWelcomePeople([
      person('plain', { localCount: 4 }),
      person('shared', { localCount: 4, sharedPlaceName: 'Fresh Monkee' }),
      person('sharedFar', { sharedPlaceName: 'Old Diner', placesCount: 50 }),
      person('far', { placesCount: 500 })
    ]);
    expect(ranked.map((p) => p.id)).toEqual(['shared', 'plain', 'sharedFar', 'far']);
    expect(ranked[0].reason).toBe('Also loves Fresh Monkee');
    expect(ranked[2].reason).toBe('Also loves Old Diner');
  });

  test('nobody at all is an empty list', () => {
    expect(rankWelcomePeople([])).toEqual([]);
  });
});
