// The app-wide search puts four lists on one screen: my places, people,
// friends' places and the FavCircles catalog. The catalog is every venue
// anyone saved, so it repeats what the first lists already show; a venue
// appears once, in the most personal list it is in.

export interface CatalogLike {
  _id: string;
  coverPhotoUrl?: string | null;
  photos?: ({ url?: string | null } | string | null)[] | null;
}

/** The catalog's photo: its cover, else its first photo (objects or plain URLs). */
export function catalogPhoto(place: CatalogLike): string | null {
  if (place.coverPhotoUrl) return place.coverPhotoUrl;
  for (const photo of place.photos || []) {
    const url = typeof photo === 'string' ? photo : photo && photo.url;
    if (url) return url;
  }
  return null;
}

/** Venue ids already shown above (a save's globalPlaceId). */
export function listedVenues(...lists: ({ globalPlaceId?: string | null }[] | undefined)[]): Set<string> {
  const ids = new Set<string>();
  lists.forEach((list) => (list || []).forEach((place) => { if (place.globalPlaceId) ids.add(place.globalPlaceId); }));
  return ids;
}

/** Catalog venues not already in a list above, in the server's order. */
export const catalogNotListed = <C extends CatalogLike>(catalog: C[] | undefined, listed: Set<string>): C[] =>
  (catalog || []).filter((venue) => !listed.has(venue._id));

/**
 * Friends' places: one row per venue (two friends saving the same café is
 * one result), first save wins, and none I saved myself.
 */
export function friendsPlacesOnce<P extends { _id: string; globalPlaceId?: string | null }>(places: P[] | undefined, mine: Set<string>): P[] {
  const seen = new Set<string>();
  return (places || []).filter((place) => {
    const venue = place.globalPlaceId || `save:${place._id}`;
    if (mine.has(venue) || seen.has(venue)) return false;
    seen.add(venue);
    return true;
  });
}
