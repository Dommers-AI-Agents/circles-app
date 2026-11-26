import { describe, expect, it } from 'vitest';
import { catalogNotListed, catalogPhoto, friendsPlacesOnce, listedVenues } from './searchResults';

describe('catalogPhoto', () => {
  it('prefers the cover', () => {
    expect(catalogPhoto({ _id: 'v', coverPhotoUrl: 'https://c', photos: [{ url: 'https://p' }] })).toBe('https://c');
  });
  it('falls back to the first photo, object or string', () => {
    expect(catalogPhoto({ _id: 'v', photos: [{ url: '' }, { url: 'https://p' }] })).toBe('https://p');
    expect(catalogPhoto({ _id: 'v', photos: ['https://s'] })).toBe('https://s');
  });
  it('is null with none', () => {
    expect(catalogPhoto({ _id: 'v' })).toBeNull();
    expect(catalogPhoto({ _id: 'v', photos: [null] })).toBeNull();
  });
});

describe('catalogNotListed', () => {
  it('drops venues already shown and keeps the order', () => {
    const listed = listedVenues([{ globalPlaceId: 'b' }], [{ globalPlaceId: null }, { globalPlaceId: 'd' }]);
    const catalog = ['a', 'b', 'c', 'd'].map((_id) => ({ _id }));
    expect(catalogNotListed(catalog, listed).map((v) => v._id)).toEqual(['a', 'c']);
  });
  it('copes with nothing loaded', () => {
    expect(catalogNotListed(undefined, new Set())).toEqual([]);
  });
});

describe('friendsPlacesOnce', () => {
  it('shows a venue once and skips my own', () => {
    const places = [
      { _id: 's1', globalPlaceId: 'g1' },
      { _id: 's2', globalPlaceId: 'g1' },
      { _id: 's3', globalPlaceId: 'g2' },
      { _id: 's4', globalPlaceId: null },
      { _id: 's5' }
    ];
    expect(friendsPlacesOnce(places, new Set(['g2'])).map((p) => p._id)).toEqual(['s1', 's4', 's5']);
  });
});
