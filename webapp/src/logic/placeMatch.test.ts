import { describe, expect, it } from 'vitest';
import { filterMyPlaces, fold, isSearchable, matchRank } from './placeMatch';

const sals = { name: "Sal's Bakery", address: '12 Main St, Charlotte, NC', category: 'cafe', circleName: 'Date night', tags: ['croissants'], privateNotes: 'Ask for the almond one' };
const cafe = { name: 'Café Moka', address: '9 Elm Ave, Asheville, NC', category: 'cafe', circleName: 'Coffee' };
const bar = { name: 'The Cellar', address: '4 Tryon St, Charlotte, NC', category: 'bar', circleName: 'Date night' };

describe('fold', () => {
  it('drops case, accents, apostrophes and punctuation', () => {
    expect(fold("  Café  Sal's — Bakery! ")).toBe('cafe sals bakery');
  });
  it('handles nothing', () => {
    expect(fold(null)).toBe('');
  });
});

describe('isSearchable', () => {
  it('needs two letters or digits', () => {
    expect(isSearchable('a')).toBe(false);
    expect(isSearchable(' a ')).toBe(false);
    expect(isSearchable('a b')).toBe(true);
    expect(isSearchable('sa')).toBe(true);
    expect(isSearchable('!!')).toBe(false);
  });
});

describe('matchRank', () => {
  it('matches the start of a word in the name', () => {
    expect(matchRank(sals, 'bak')).toBe(2);
    expect(matchRank(sals, 'sal')).toBe(2);
  });
  it('does not match the middle of a word', () => {
    expect(matchRank(sals, 'akery')).toBe(0);
  });
  it('ignores accents and apostrophes both ways', () => {
    expect(matchRank(cafe, 'cafe')).toBe(2);
    expect(matchRank(sals, 'sals')).toBe(2);
    expect(matchRank(sals, "sal's")).toBe(2);
  });
  it('needs every word, in any order', () => {
    expect(matchRank(sals, 'bakery sal')).toBe(2);
    expect(matchRank(sals, 'bakery pizza')).toBe(0);
  });
  it('lets the address, circle, kind, tags and notes help', () => {
    expect(matchRank(sals, 'charlotte')).toBe(1);
    expect(matchRank(sals, 'date night')).toBe(1);
    expect(matchRank(sals, 'croiss')).toBe(1);
    expect(matchRank(sals, 'almond')).toBe(1);
    expect(matchRank(bar, 'bar')).toBe(1);
    expect(matchRank(sals, 'bakery charlotte')).toBe(1);
  });
  it('matches the kind of place by its shown name too', () => {
    expect(matchRank({ name: 'REI', category: 'retail' }, 'shop')).toBe(1);
  });
  it('never matches an empty search', () => {
    expect(matchRank(sals, '   ')).toBe(0);
  });
});

describe('filterMyPlaces', () => {
  const places = [bar, sals, cafe];
  it('returns nothing for a search too short to mean anything', () => {
    expect(filterMyPlaces(places, 'c')).toEqual([]);
  });
  it('puts name matches first and keeps the given order inside each group', () => {
    // "ch" is in no name: both come from the address, in the order given
    expect(filterMyPlaces(places, 'ch').map((p) => p.name)).toEqual(['The Cellar', "Sal's Bakery"]);
    expect(filterMyPlaces(places, 'caf').map((p) => p.name)).toEqual(['Café Moka', "Sal's Bakery"]);
  });
  it('stops at the limit', () => {
    expect(filterMyPlaces(places, 'nc', 2)).toHaveLength(2);
  });
});
