const { namesLikelySameVenue, sharedWords, googleIdsConflict } = require('../venueNameMatch');

describe('namesLikelySameVenue', () => {
  test('Sal’s two names for the Atlantic Club match', () => {
    const a = 'Genesis/Atlantic Health Club';
    const b = 'Genesis Health Clubs - The Atlantic Club Manasquan';
    expect(sharedWords(a, b).sort()).toEqual(['atlantic', 'genesis']);
    expect(namesLikelySameVenue(a, b)).toBe(true);
  });

  test('neighbours that share only a kind-of-place word stay apart', () => {
    expect(namesLikelySameVenue('Pizza Hut', 'Pizza Palace')).toBe(false);
    expect(namesLikelySameVenue('Crunch Fitness', 'Planet Fitness')).toBe(false);
    expect(namesLikelySameVenue('The Coffee Bar', 'Coffee Corner Bar')).toBe(false);
  });

  test('one shared distinctive word is not enough', () => {
    expect(namesLikelySameVenue('Chelsea Market', 'Chelsea Market Baskets')).toBe(false);
    expect(namesLikelySameVenue('Starbucks', 'Starbucks Reserve Roastery')).toBe(false);
  });

  test('plurals and punctuation fold', () => {
    expect(namesLikelySameVenue("Valente's Italian Deli", 'Valentes Italian Delis')).toBe(true);
  });

  test('empty names never match', () => {
    expect(namesLikelySameVenue('', 'Anything Here')).toBe(false);
    expect(namesLikelySameVenue(null, undefined)).toBe(false);
  });
});

describe('googleIdsConflict', () => {
  test('two different Google ids are two venues', () => {
    expect(googleIdsConflict('ChIJa', 'ChIJb')).toBe(true);
  });
  test('missing or equal ids do not conflict', () => {
    expect(googleIdsConflict('ChIJa', 'ChIJa')).toBe(false);
    expect(googleIdsConflict(null, 'ChIJb')).toBe(false);
    expect(googleIdsConflict(undefined, undefined)).toBe(false);
  });
});
