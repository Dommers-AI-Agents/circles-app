import { describe, expect, it } from 'vitest';
import { linkParts, safeHttpUrl } from './chatLinks';

describe('linkParts', () => {
  it('leaves plain text alone', () => {
    expect(linkParts('See you at 7')).toEqual([{ kind: 'text', text: 'See you at 7' }]);
    expect(linkParts('')).toEqual([]);
  });

  it('finds links among words', () => {
    expect(linkParts('Menu: https://sals.example/menu ok?')).toEqual([
      { kind: 'text', text: 'Menu: ' },
      { kind: 'link', text: 'https://sals.example/menu', href: 'https://sals.example/menu' },
      { kind: 'text', text: ' ok?' }
    ]);
  });

  it('drops the sentence end from a link and adds https to www', () => {
    expect(linkParts('Try www.favcircles.com.')).toEqual([
      { kind: 'text', text: 'Try ' },
      { kind: 'link', text: 'www.favcircles.com', href: 'https://www.favcircles.com' },
      { kind: 'text', text: '.' }
    ]);
  });

  it('keeps a bracket that belongs to the link', () => {
    const parts = linkParts('(https://en.wikipedia.org/wiki/Pizza_(disambiguation))');
    expect(parts[1]).toEqual({ kind: 'link', text: 'https://en.wikipedia.org/wiki/Pizza_(disambiguation)', href: 'https://en.wikipedia.org/wiki/Pizza_(disambiguation)' });
    expect(parts[2]).toEqual({ kind: 'text', text: ')' });
  });

  it('finds several links', () => {
    expect(linkParts('a http://x.io b https://y.io').filter((p) => p.kind === 'link').map((p) => p.text)).toEqual(['http://x.io', 'https://y.io']);
  });
});

describe('safeHttpUrl', () => {
  it('lets only web links through', () => {
    expect(safeHttpUrl('https://maps.apple.com/?ll=1,2')).toBe('https://maps.apple.com/?ll=1,2');
    expect(safeHttpUrl('javascript:alert(1)')).toBeUndefined();
    expect(safeHttpUrl('data:text/html,hi')).toBeUndefined();
    expect(safeHttpUrl('not a url')).toBeUndefined();
    expect(safeHttpUrl(null)).toBeUndefined();
  });
});
