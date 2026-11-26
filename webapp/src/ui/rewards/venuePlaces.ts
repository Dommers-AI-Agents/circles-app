// A store's rewards are loaded by its place (GET /rewards/venues/by-place/
// :placeId); no endpoint takes a venueId. Every link to a store's rewards
// carries the place as ?p=, and what this phone has seen is remembered so a
// row that only knows the venueId (a ticket, a coupon) still opens.
const KEY = 'fc.web.venuePlaces';

function read(): Record<string, string> {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) || '{}');
    return value && typeof value === 'object' ? value : {};
  } catch {
    return {};
  }
}

export function rememberVenuePlace(venueId: string | undefined | null, globalPlaceId: string | undefined | null): void {
  if (!venueId || !globalPlaceId) return;
  const map = read();
  if (map[venueId] === globalPlaceId) return;
  map[venueId] = globalPlaceId;
  try {
    localStorage.setItem(KEY, JSON.stringify(map));
  } catch {
    // Private mode: the link's ?p= still works
  }
}

export const venuePlaceOf = (venueId: string): string | undefined => read()[venueId];

/** The store's rewards page; remembers the place on the way. */
export function storeRewardsPath(venueId: string, globalPlaceId?: string | null): string {
  rememberVenuePlace(venueId, globalPlaceId);
  const place = globalPlaceId || venuePlaceOf(venueId);
  return `/rewards/${encodeURIComponent(venueId)}${place ? `?p=${encodeURIComponent(place)}` : ''}`;
}
