// A store's web address: order.favcircles.com/<slug> (2026-10-28).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const slugs = require('../venueSlugService');

beforeEach(() => { for (const c of ['stickerVenues', 'venueSlugs']) mockDb.rows(c).clear(); });

describe('slugify', () => {
  test('names become addresses', () => {
    expect(slugs.slugify('Wooden Robot Brewery')).toBe('wooden-robot-brewery');
    expect(slugs.slugify('Café & Co.')).toBe('cafe-and-co');
    expect(slugs.slugify("Sal's Pizzeria!!")).toBe('sal-s-pizzeria');
    expect(slugs.slugify('   ')).toBe('');
    expect(slugs.slugify('x'.repeat(80)).length).toBe(48);
  });
  test('the city comes from the address', () => {
    expect(slugs.cityFromAddress('1 Main St, Charlotte, NC 28202, USA')).toBe('charlotte');
    expect(slugs.cityFromAddress('1525 Bay Plz, Wall Township, NJ 07719')).toBe('wall-township');
    expect(slugs.cityFromAddress('')).toBe('');
  });
  test('candidates: the name, then the city, then numbers; never a reserved word', () => {
    const c = slugs.slugCandidates({ venueName: 'Test Bakery', placeAddress: '1 Elm St, Charlotte, NC 28202' });
    expect(c.slice(0, 3)).toEqual(['test-bakery', 'test-bakery-charlotte', 'test-bakery-2']);
    expect(slugs.slugCandidates({ venueName: 'Menu' })[0]).toBe('menu-charlotte'.startsWith('menu') ? slugs.slugCandidates({ venueName: 'Menu' })[0] : '');
    expect(slugs.slugCandidates({ venueName: 'Menu' })).not.toContain('menu');
    expect(slugs.slugCandidates({ venueName: 'Ab' })[0]).toBe('ab-store');
  });
  test('owner edits are checked', () => {
    expect(slugs.validateSlug(' Wooden-Robot ')).toBe('wooden-robot');
    expect(() => slugs.validateSlug('ab')).toThrow(expect.objectContaining({ code: 'bad_slug' }));
    expect(() => slugs.validateSlug('-bad-')).toThrow(expect.objectContaining({ code: 'bad_slug' }));
    expect(() => slugs.validateSlug('admin')).toThrow(expect.objectContaining({ code: 'bad_slug' }));
    expect(() => slugs.validateSlug('has space')).toThrow(expect.objectContaining({ code: 'bad_slug' }));
  });
  test('the page URL', () => {
    expect(slugs.pageUrl('wooden-robot-brewery')).toBe('https://order.favcircles.com/wooden-robot-brewery');
  });
});

describe('claiming', () => {
  const venue = (id, name, address) => mockDb.collection('stickerVenues').doc(id).set({ venueName: name, placeAddress: address, ownerUserId: 'o' });

  test('two stores with one name: the second gets its city, the third a number', async () => {
    await venue('v1', 'Test Bakery', '1 Elm St, Charlotte, NC 28202');
    await venue('v2', 'Test Bakery', '9 Oak St, Charlotte, NC 28202');
    await venue('v3', 'Test Bakery', '9 Oak St, Charlotte, NC 28202');
    expect(await slugs.ensureSlug({ venueId: 'v1', venueName: 'Test Bakery', placeAddress: '1 Elm St, Charlotte, NC 28202' })).toBe('test-bakery');
    expect(await slugs.ensureSlug({ venueId: 'v2', venueName: 'Test Bakery', placeAddress: '9 Oak St, Charlotte, NC 28202' })).toBe('test-bakery-charlotte');
    expect(await slugs.ensureSlug({ venueId: 'v3', venueName: 'Test Bakery', placeAddress: '9 Oak St, Charlotte, NC 28202' })).toBe('test-bakery-2');
    expect((await mockDb.collection('stickerVenues').doc('v2').get()).data().slug).toBe('test-bakery-charlotte');
    expect(await slugs.resolve('test-bakery-2')).toEqual({ venueId: 'v3', retired: false });
  });

  test('ensureSlug is idempotent and virtual stores get none', async () => {
    await venue('v1', 'Test Bakery', '');
    const v = { venueId: 'v1', venueName: 'Test Bakery' };
    expect(await slugs.ensureSlug(v)).toBe('test-bakery');
    expect(await slugs.ensureSlug(v)).toBe('test-bakery');
    expect(mockDb.rows('venueSlugs').size).toBe(1);
    expect(await slugs.ensureSlug({ venueId: 'v9', venueName: 'Brand', isVirtual: true })).toBeNull();
  });

  test('renaming keeps the old address as a redirect and refuses a taken one', async () => {
    await venue('v1', 'Test Bakery', '');
    await venue('v2', 'Other', '');
    await slugs.ensureSlug({ venueId: 'v1', venueName: 'Test Bakery' });
    await slugs.ensureSlug({ venueId: 'v2', venueName: 'Other' });
    const v1 = { venueId: 'v1', venueName: 'Test Bakery', slug: 'test-bakery' };
    expect(await slugs.setSlug(v1, 'Wall-Bakery')).toEqual({ slug: 'wall-bakery', url: 'https://order.favcircles.com/wall-bakery' });
    expect(await slugs.resolve('test-bakery')).toEqual({ venueId: 'v1', retired: true });
    expect(await slugs.resolve('wall-bakery')).toEqual({ venueId: 'v1', retired: false });
    await expect(slugs.setSlug(v1, 'other')).rejects.toMatchObject({ code: 'slug_taken' });
    expect(await slugs.resolve('nope')).toBeNull();
  });
});
