import { describe, expect, it } from 'vitest';
import { mergeVenueResults, nameWords, sameName, type VenueResult } from './venueResults';

const venue = (over: Partial<VenueResult> & { key: string; name: string }): VenueResult => ({
  address: '1 Main St', at: { lat: 35.2243, lng: -80.8452 }, category: 'cafe', source: 'osm', ...over
});
// ~0.001° of latitude is ~111 m
const north = (meters: number) => ({ lat: 35.2243 + meters / 111000, lng: -80.8452 });

describe('names', () => {
  it('drops accents, case and punctuation', () => {
    expect(nameWords("Amélie's French Bakery & Café")).toEqual(['amelies', 'french', 'bakery', 'and', 'cafe']);
  });
  it('treats small differences as the same name', () => {
    expect(sameName("Amelie's French Bakery & Café", 'Amelies French Bakery and Cafe')).toBe(true);
    expect(sameName('Starbucks', 'Starbucks Reserve')).toBe(true);
    expect(sameName('The Optimist Hall', 'Optimist Hall')).toBe(true);
    expect(sameName("Amélie's Uptown | French Bakery & Cafe", "Amelie's French Bakery & Café")).toBe(true);
  });
  it('keeps different places apart', () => {
    expect(sameName('Starbucks', 'Dunkin')).toBe(false);
    expect(sameName('Bar', 'Bar Marcel')).toBe(false);
    expect(sameName('Soho Bistro', 'Soho House')).toBe(false);
    expect(sameName('', 'Anything')).toBe(false);
    expect(sameName('&', 'The')).toBe(false);
  });
});

describe('mergeVenueResults', () => {
  const catalog = venue({ key: 'g1', name: "Amélie's French Bakery & Cafe", source: 'catalog', globalPlaceId: 'g1' });

  it('lists the catalog first and leaves out the same venue from OpenStreetMap', () => {
    const merged = mergeVenueResults([catalog], [
      venue({ key: 'N1', name: "Amelie's French Bakery and Café", at: north(60) }),
      venue({ key: 'N2', name: 'Queen City Grounds', at: north(60) })
    ]);
    expect(merged.map((v) => v.key)).toEqual(['g1', 'N2']);
  });

  it('keeps a same-named place that is somewhere else (another branch)', () => {
    const merged = mergeVenueResults([catalog], [venue({ key: 'N3', name: "Amelie's French Bakery & Café", at: north(400) })]);
    expect(merged.map((v) => v.key)).toEqual(['g1', 'N3']);
  });

  it('keeps a different place next door', () => {
    const merged = mergeVenueResults([catalog], [venue({ key: 'N4', name: 'Rhino Market', at: north(10) })]);
    expect(merged).toHaveLength(2);
  });

  it('removes repeats inside the OpenStreetMap results too, and never a catalog venue', () => {
    const twin = venue({ key: 'g2', name: "Amélie's French Bakery & Cafe", source: 'catalog', globalPlaceId: 'g2' });
    const merged = mergeVenueResults([catalog, twin], [
      venue({ key: 'N5', name: 'Rhino Market' }),
      venue({ key: 'W5', name: 'Rhino Market', at: north(20) }),
      venue({ key: 'N5', name: 'Rhino Market' })
    ]);
    expect(merged.map((v) => v.key)).toEqual(['g1', 'g2', 'N5']);
  });

  it('works with either list empty', () => {
    expect(mergeVenueResults([], [])).toEqual([]);
    expect(mergeVenueResults([catalog], [])).toEqual([catalog]);
    expect(mergeVenueResults([], [venue({ key: 'N6', name: 'Solo' })])).toHaveLength(1);
  });
});
