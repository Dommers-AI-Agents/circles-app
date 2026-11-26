// The map's pins and the Add Place calls (search and save).
import { get, post } from './client';
import type { Circle, GeoPoint, Place } from './types';
import { latLngOf, type LatLng } from '../logic/geo';
import { clampRadius } from '../logic/pinTiers';
import type { SaveBody } from '../logic/addPlace';
import { mergeVenueResults, type VenueResult } from '../logic/venueResults';

/** What a pin needs. The server's lean shape names the id `id`. */
export interface MapPin {
  id: string;
  name: string;
  address: string;
  at: LatLng;
  category: string;
  circleId: string | null;
  addedBy: string | null;
}

interface LeanPlace {
  id?: string;
  _id?: string;
  name?: string;
  address?: string | null;
  location?: GeoPoint | null;
  category?: string;
  circleId?: string | null;
  addedBy?: string | null;
}

const pinOf = (place: LeanPlace): MapPin | null => {
  const id = place.id || place._id;
  const at = latLngOf(place.location);
  if (!id || !at) return null;
  return {
    id, at, name: place.name || 'Unnamed place', address: place.address || '', category: place.category || 'other',
    circleId: place.circleId || null, addedBy: place.addedBy || null
  };
};
const pinsOf = (places: LeanPlace[] | undefined): MapPin[] =>
  (places || []).map(pinOf).filter((pin): pin is MapPin => pin !== null);

/** Circles whose places belong on my map (a circle can be switched off the map). */
export const circlesOnMap = (circles: Circle[]): Circle[] => circles.filter((c) => c.showOnMap !== false && !c.locked);

const BATCH = 50;

/** Every place in these circles, as pins. The server takes 50 circles a call. */
export async function myMapPins(circleIds: string[]): Promise<MapPin[]> {
  const calls: Promise<{ places: LeanPlace[] }>[] = [];
  for (let i = 0; i < circleIds.length; i += BATCH) {
    calls.push(post<{ places: LeanPlace[] }>('/places/batch', { circleIds: circleIds.slice(i, i + BATCH), lean: true }));
  }
  const seen = new Set<string>();
  return (await Promise.all(calls))
    .flatMap((answer) => pinsOf(answer.places))
    .filter((pin) => (seen.has(pin.id) ? false : (seen.add(pin.id), true)));
}

export interface FriendsView {
  pins: MapPin[];
  /** More places in this area than were sent: zooming in shows them */
  hasMore: boolean;
}

/** Places my network saved inside the area on screen (it includes my own: the caller drops those). */
export const friendsPins = (center: LatLng, radiusM: number, signal?: AbortSignal): Promise<FriendsView> =>
  get<{ places: LeanPlace[]; hasMore?: boolean }>('/network/places/viewport', {
    centerLat: center.lat.toFixed(5), centerLng: center.lng.toFixed(5), radiusM: clampRadius(radiusM), limit: 200, lean: 1
  }, signal).then((answer) => ({ pins: pinsOf(answer.places), hasMore: answer.hasMore === true }));

// ---- Add Place: finding the venue

interface CatalogVenue {
  _id?: string;
  id?: string;
  name?: string;
  address?: string | null;
  location?: GeoPoint | null;
  category?: string;
  coverPhotoUrl?: string | null;
  /** The venue's photo library: plain URLs or { url, removedAt } entries */
  photos?: (string | { url?: string; removedAt?: string | null } | null)[];
}

const firstPhoto = (venue: CatalogVenue): string | null => {
  if (venue.coverPhotoUrl) return venue.coverPhotoUrl;
  for (const photo of venue.photos || []) {
    if (typeof photo === 'string' && photo) return photo;
    if (photo && typeof photo === 'object' && photo.url && !photo.removedAt) return photo.url;
  }
  return null;
};

interface WebVenue {
  name: string;
  address: string;
  location: GeoPoint;
  category: string;
  source: 'osm';
  osmId: string;
}

const fromCatalog = (venue: CatalogVenue): VenueResult | null => {
  const id = venue._id || venue.id;
  const at = latLngOf(venue.location);
  if (!id || !at || !venue.name) return null;
  return {
    key: `catalog:${id}`, name: venue.name, address: venue.address || '', at, category: venue.category || 'other',
    source: 'catalog', globalPlaceId: id, photo: firstPhoto(venue)
  };
};

const fromWeb = (venue: WebVenue): VenueResult | null => {
  const at = latLngOf(venue.location);
  if (!at || !venue.name) return null;
  return { key: `osm:${venue.osmId}`, name: venue.name, address: venue.address || '', at, category: venue.category || 'other', source: 'osm' };
};

const present = <T,>(value: T | null): value is T => value !== null;

export interface VenueSearch {
  results: VenueResult[];
  /** The wider (OpenStreetMap) search didn't answer: only FavCircles places are listed */
  webFailed: boolean;
  /** Some results came from OpenStreetMap, so its credit is shown */
  hasWebResults: boolean;
}

/**
 * Both sources at once. `near` is where the person is, when known: the
 * catalog then looks within 80 km of it. `bias` leans the wider search
 * toward somewhere (never a hard limit). One source failing still lists the
 * other; both failing is an error.
 */
export async function searchVenues(query: string, near: LatLng | null, bias: LatLng, signal?: AbortSignal): Promise<VenueSearch> {
  const [catalog, web] = await Promise.allSettled([
    get<{ data: CatalogVenue[] }>('/places/global/search', {
      query, lat: near ? near.lat : undefined, lng: near ? near.lng : undefined, radius: near ? 80 : undefined, limit: 20
    }, signal),
    get<{ data: WebVenue[] }>('/places/web-search', { q: query, lat: bias.lat.toFixed(4), lng: bias.lng.toFixed(4) }, signal)
  ]);
  if (catalog.status === 'rejected' && web.status === 'rejected') throw catalog.reason;
  const catalogResults = catalog.status === 'fulfilled' ? (catalog.value.data || []).map(fromCatalog).filter(present) : [];
  const webResults = web.status === 'fulfilled' ? (web.value.data || []).map(fromWeb).filter(present) : [];
  const results = mergeVenueResults(catalogResults, webResults);
  return { results, webFailed: web.status === 'rejected', hasWebResults: results.some((r) => r.source === 'osm') };
}

// ---- Add Place: saving

/** 201 → the new save. `approvalStatus: 'pending'` = saved private until reviewed. */
export const savePlace = (body: SaveBody) => post<{ place: Place }>('/places', body).then((r) => r.place);
