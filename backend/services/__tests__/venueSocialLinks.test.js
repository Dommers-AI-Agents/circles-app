jest.mock('../../config/firebase', () => ({ getFirestore: () => ({ collection: jest.fn() }) }));

const { normalizeSocialLink, socialLinksOf } = require('../venueSocialLinks');
const { buildDetailUpdates, pickDetailFields, detailsOf } = require('../venueDetailsService');

describe('a store\'s social links (Wes, 2026-11-24)', () => {
  test('a handle becomes the page on that network', () => {
    expect(normalizeSocialLink('instagram', '@giddygoat')).toBe('https://www.instagram.com/giddygoat');
    expect(normalizeSocialLink('instagram', ' giddy.goat_clt ')).toBe('https://www.instagram.com/giddy.goat_clt');
    expect(normalizeSocialLink('facebook', 'GiddyGoatCoffee')).toBe('https://www.facebook.com/GiddyGoatCoffee');
    expect(normalizeSocialLink('twitter', '@giddygoat')).toBe('https://x.com/giddygoat');
  });

  test('a pasted address is kept, on https, without tracking', () => {
    expect(normalizeSocialLink('instagram', 'instagram.com/giddygoat/?hl=en')).toBe('https://instagram.com/giddygoat');
    expect(normalizeSocialLink('instagram', 'http://www.instagram.com/giddygoat/')).toBe('https://www.instagram.com/giddygoat');
    expect(normalizeSocialLink('facebook', 'https://m.facebook.com/GiddyGoatCoffee')).toBe('https://www.facebook.com/GiddyGoatCoffee');
    expect(normalizeSocialLink('twitter', 'https://twitter.com/giddygoat?s=20')).toBe('https://twitter.com/giddygoat');
    expect(normalizeSocialLink('twitter', 'x.com/giddygoat')).toBe('https://x.com/giddygoat');
  });

  test('a Facebook page known only by its number keeps the number', () => {
    expect(normalizeSocialLink('facebook', 'https://www.facebook.com/profile.php?id=100064')).toBe('https://www.facebook.com/profile.php?id=100064');
  });

  test('blank removes the link', () => {
    expect(normalizeSocialLink('instagram', '')).toBeNull();
    expect(normalizeSocialLink('facebook', '   ')).toBeNull();
    expect(normalizeSocialLink('twitter', null)).toBeNull();
  });

  test('a link to somewhere else is refused', () => {
    expect(() => normalizeSocialLink('instagram', 'https://evil.example/giddygoat')).toThrow(/Instagram/);
    expect(() => normalizeSocialLink('instagram', 'https://instagram.com.evil.example/x')).toThrow();
    expect(() => normalizeSocialLink('facebook', 'https://instagram.com/giddygoat')).toThrow(/Facebook/);
    expect(() => normalizeSocialLink('twitter', 'javascript:alert(1)')).toThrow();
    expect(() => normalizeSocialLink('instagram', 'two words')).toThrow();
    // The network's front page is not the store's page
    expect(() => normalizeSocialLink('instagram', 'https://instagram.com/')).toThrow();
    expect(() => normalizeSocialLink('instagram', 'instagram.com')).toThrow();
  });

  test('they are store details: written on the venue record, nothing on saves', () => {
    const fields = pickDetailFields({ instagram: '@giddygoat', twitter: '', notes: 'mine' });
    expect(fields).toEqual({ instagram: '@giddygoat', twitter: '' });
    const { venue, cache } = buildDetailUpdates(fields);
    expect(venue).toEqual({
      'socialLinks.instagram': 'https://www.instagram.com/giddygoat',
      'socialLinks.twitter': null
    });
    expect(cache).toEqual({});
  });

  test('readers get only the links that are set, or nothing', () => {
    expect(socialLinksOf({ socialLinks: { instagram: 'https://www.instagram.com/a', facebook: null, twitter: '' } }))
      .toEqual({ instagram: 'https://www.instagram.com/a' });
    expect(socialLinksOf({ socialLinks: { facebook: null } })).toBeNull();
    expect(socialLinksOf({})).toBeNull();
    expect(detailsOf('g1', { name: 'A' }).socialLinks).toBeNull();
  });
});
