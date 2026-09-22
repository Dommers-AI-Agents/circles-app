// The storefront rules: what an owner may put on their page, and what a
// customer sees of it depending on whether the store's paid features are on.
const sf = require('../venueStorefront');

describe('offerings', () => {
  it('names the block by what the store sells', () => {
    expect(sf.offeringsLabel('restaurant')).toBe('Menu');
    expect(sf.offeringsLabel('cafe')).toBe('Menu');
    expect(sf.offeringsLabel('hotel')).toBe('Rooms');
    expect(sf.offeringsLabel('retail')).toBe('Products');
    expect(sf.offeringsLabel('service')).toBe('Services');
    expect(sf.offeringsLabel('attraction')).toBe('What we offer');
  });

  it('keeps a link, files and featured items, trimmed and capped', () => {
    const { value, errors } = sf.normalizeOfferings({
      link: ' https://example.com/menu ',
      files: [{ url: 'https://x/menu.pdf', kind: 'pdf', label: ' Dinner ' }],
      featured: [{ name: ' Cacio e Pepe ', price: '$18', description: 'x', tags: ['Popular', 'GF', 'Veg', 'Extra'] }]
    });
    expect(errors).toEqual([]);
    expect(value.link).toBe('https://example.com/menu');
    expect(value.files[0]).toMatchObject({ url: 'https://x/menu.pdf', kind: 'pdf', label: 'Dinner' });
    expect(value.featured[0].name).toBe('Cacio e Pepe');
    expect(value.featured[0].tags).toEqual(['Popular', 'GF', 'Veg']); // capped at 3
    expect(value.featured[0].itemId).toMatch(/^item_/);
  });

  it('refuses the things that would break the page', () => {
    const { errors } = sf.normalizeOfferings({
      link: 'javascript:alert(1)',
      files: [{ url: 'not a url' }],
      featured: [{ name: '' }, { name: 'ok', photoUrl: 'ftp://x' }]
    });
    expect(errors).toEqual(expect.arrayContaining([
      'link must be a web address',
      'files[0].url must be a web address',
      'featured[0].name is required',
      'featured[1].photoUrl must be a web address'
    ]));
  });

  it('caps featured items and gallery photos', () => {
    const many = Array.from({ length: 9 }, (_, i) => ({ name: `Item ${i}` }));
    expect(sf.normalizeOfferings({ featured: many }).errors).toContain('at most 8 featured items');
    const photos = Array.from({ length: 13 }, (_, i) => ({ url: `https://x/${i}.jpg` }));
    expect(sf.normalizeGallery(photos).errors).toContain('at most 12 gallery photos');
  });
});

describe('actions', () => {
  it('keeps the four money buttons and drops the rest', () => {
    const { value, errors } = sf.normalizeActions({ reserve: 'https://resy.com/x', order: '', evil: 'https://y', book: null });
    expect(errors).toEqual([]);
    expect(value).toEqual({ reserve: 'https://resy.com/x', order: null, catering: null, book: null });
  });

  it('refuses a non-web link', () => {
    expect(sf.normalizeActions({ order: 'tel:123' }).errors).toEqual(['order must be a web address']);
  });
});

describe('what the customer sees', () => {
  const venue = {
    category: 'restaurant',
    storefront: {
      offerings: { link: 'https://x/menu', files: [], featured: [{ itemId: 'a', name: 'Rigatoni' }] },
      actions: { reserve: 'https://resy.com/x', order: null, catering: null, book: null },
      gallery: [{ photoId: 'p', url: 'https://x/1.jpg', caption: null }]
    }
  };

  it('shows everything when the store is live', () => {
    const pub = sf.publicStorefront(venue, { live: true });
    expect(pub.offeringsLabel).toBe('Menu');
    expect(pub.offerings.featured).toHaveLength(1);
    expect(pub.gallery).toHaveLength(1);
    expect(pub.actions.reserve).toBe('https://resy.com/x');
  });

  it('keeps the buttons and hides the paid blocks when the subscription lapsed', () => {
    // A lapsed owner shouldn't keep broadcasting a paid feature — same rule
    // as announcements. The Reserve button still helps the customer.
    const pub = sf.publicStorefront(venue, { live: false });
    expect(pub.offerings).toBeNull();
    expect(pub.gallery).toEqual([]);
    expect(pub.actions.reserve).toBe('https://resy.com/x');
  });

  it('is nothing at all for a venue with nothing set', () => {
    expect(sf.publicStorefront({ category: 'cafe' }, { live: true })).toBeNull();
    expect(sf.publicStorefront({ category: 'cafe', storefront: { actions: { reserve: null } } }, { live: true })).toBeNull();
  });

  it('gives the owner the full editable shape even when empty', () => {
    const own = sf.ownerStorefront({ category: 'retail' });
    expect(own).toEqual({
      offeringsLabel: 'Products',
      offerings: { link: null, files: [], featured: [] },
      actions: { reserve: null, order: null, catering: null, book: null },
      gallery: []
    });
  });
});
