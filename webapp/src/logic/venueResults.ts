// Add Place search results come from two places: the FavCircles catalog
// (venues people already saved) and OpenStreetMap (the server's web search).
// One list: the catalog first, and an OpenStreetMap result that is the same
// venue (same name within ~150 m) left out, so nobody saves a second copy of
// a place the app already knows.
import { distanceMeters, type LatLng } from './geo';

export interface VenueResult {
  /** Unique in the list */
  key: string;
  name: string;
  address: string;
  at: LatLng;
  category: string;
  source: 'catalog' | 'osm';
  /** Catalog results only: the venue to save against */
  globalPlaceId?: string;
  photo?: string | null;
}

const SAME_VENUE_METERS = 150;

/** "Amélie's French Bakery & Café" → ["amelies", "french", "bakery", "and", "cafe"] */
export function nameWords(name: string): string[] {
  return name
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/['’`.]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(' ')
    .filter(Boolean);
}

/**
 * The same name, give or take: identical once accents, case and punctuation
 * are gone, or one is the other with a few more words ("Starbucks" and
 * "Starbucks Reserve"; "Amelie's French Bakery" and "Amelie's French Bakery
 * and Cafe"). "and"/"the" never decide it.
 */
export function sameName(a: string, b: string): boolean {
  const filler = new Set(['and', 'the']);
  const wordsA = nameWords(a).filter((w) => !filler.has(w));
  const wordsB = nameWords(b).filter((w) => !filler.has(w));
  if (wordsA.length === 0 || wordsB.length === 0) return false;
  const [short, long] = wordsA.length <= wordsB.length ? [wordsA, wordsB] : [wordsB, wordsA];
  if (short.join('').length < 4 && short.length !== long.length) return false;
  const pool = new Set(long);
  return short.every((word) => pool.has(word));
}

export const sameVenue = (a: VenueResult, b: VenueResult): boolean =>
  distanceMeters(a.at, b.at) <= SAME_VENUE_METERS && sameName(a.name, b.name);

/** Catalog first (in its own order), then the OpenStreetMap results that aren't already listed. */
export function mergeVenueResults(catalog: VenueResult[], web: VenueResult[]): VenueResult[] {
  const merged: VenueResult[] = [];
  const keys = new Set<string>();
  for (const venue of [...catalog, ...web]) {
    if (keys.has(venue.key)) continue;
    if (venue.source === 'osm' && merged.some((kept) => sameVenue(kept, venue))) continue;
    keys.add(venue.key);
    merged.push(venue);
  }
  return merged;
}
