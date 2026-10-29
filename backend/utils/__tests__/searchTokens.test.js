const { buildSearchTokens, queryTokens, anchorToken, hasAllTokens, foldText } = require('../searchTokens');

describe('searchTokens', () => {
  test('accents fold so "cafe" finds "Café"', () => {
    expect(buildSearchTokens('Café Rio')).toEqual(expect.arrayContaining(['cafe', 'rio', 'c']));
    expect(queryTokens('CAFÉ')).toEqual(['cafe']);
  });

  test('an apostrophe both joins and splits the stored word', () => {
    const tokens = buildSearchTokens("Nickyo's Rodeo");
    expect(tokens).toEqual(expect.arrayContaining(['nickyos', 'nickyo', 's', 'rodeo']));
    expect(hasAllTokens(tokens, queryTokens("nickyo's"))).toBe(true);
    expect(hasAllTokens(tokens, queryTokens('nickyos rod'))).toBe(true);
  });

  test('words cap at 20 characters, duplicates collapse', () => {
    const tokens = buildSearchTokens('Supercalifragilisticexpialidocious super');
    expect(Math.max(...tokens.map(t => t.length))).toBe(20);
    expect(new Set(tokens).size).toBe(tokens.length);
  });

  test('several texts tokenize together (first/last/display names)', () => {
    const tokens = buildSearchTokens('Sal S.', 'Salvatore', 'Smith');
    expect(tokens).toEqual(expect.arrayContaining(['salvatore', 'smith', 'sal']));
  });

  test('anchor is the longest word; empty input is safe', () => {
    expect(anchorToken(['a', 'pizza', 'nyc'])).toBe('pizza');
    expect(queryTokens('')).toEqual([]);
    expect(buildSearchTokens(null)).toEqual([]);
    expect(foldText(undefined)).toBe('');
  });
});
