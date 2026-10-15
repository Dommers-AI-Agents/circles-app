const { TABS, GENERIC, tabCopy } = require('../homeTabCatalog');

describe('shared home tab landing copy', () => {
  test('the two shareable tabs have their own page', () => {
    expect(Object.keys(TABS).sort()).toEqual(['local', 'widgets']);
    expect(tabCopy('local').title).toBe('Local');
    expect(tabCopy('Widgets').title).toBe('Widgets'); // case never matters in a link
  });

  test('an unknown or missing slug falls back to the app pitch, never a 404', () => {
    expect(tabCopy('moments')).toBe(GENERIC);
    expect(tabCopy('')).toBe(GENERIC);
    expect(tabCopy(undefined)).toBe(GENERIC);
  });
});
