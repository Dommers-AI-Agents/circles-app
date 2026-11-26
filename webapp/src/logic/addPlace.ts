// Add Place, as rules: what a new save sends (POST /places), which circle it
// starts on, and what the server's answer means for the person. Pure.
import type { Circle, GeoPoint, PlacePrivacy } from '../api/types';
import { pointOf, type LatLng } from './geo';
import { CATEGORIES } from './labels';
import { startingCircle } from './placeSave';

/** The venue the person picked: from the FavCircles catalog, OpenStreetMap, or typed by hand. */
export interface PickedVenue {
  name: string;
  address: string;
  at: LatLng;
  category: string;
  source: 'catalog' | 'osm' | 'hand';
  /** Catalog picks only: the venue record the save is for */
  globalPlaceId?: string;
}

export interface SaveChoices {
  circleId: string;
  category: string;
  privacy: PlacePrivacy;
  privateNotes: string;
  userRating: number | null;
}

/** The POST /places body (backend/services/placeSaveService.js). */
export interface SaveBody {
  name: string;
  address: string;
  location: GeoPoint;
  category: string;
  circleId: string;
  privacy: PlacePrivacy;
  privateNotes?: string;
  userRating?: number;
  globalPlaceId?: string;
  force?: true;
}

const NAME_MAX = 120;
const ADDRESS_MAX = 300;
const NOTES_MAX = 2000;

const tidy = (text: string, max: number) => text.replace(/\s+/g, ' ').trim().slice(0, max);

/** A category id the server accepts; anything else is "other". */
export const knownCategory = (id: string | null | undefined): string =>
  CATEGORIES.some((c) => c.id === id) ? String(id) : 'other';

/** "35.22710, -80.84310": the address of a pin with no street address. */
export const coordinatesText = ({ lat, lng }: LatLng): string => `${lat.toFixed(5)}, ${lng.toFixed(5)}`;

/**
 * The body for a new save. A catalog pick is sent with the catalog's own
 * name and address and its venue id, so the save joins that venue instead of
 * minting a second one. Nothing claims a map source vouched for the place:
 * an OpenStreetMap or typed place is matched (or held for review) by the
 * server. `force` only on "Add anyway".
 */
export function buildSaveBody(venue: PickedVenue, choices: SaveChoices, options: { force?: boolean } = {}): SaveBody {
  const body: SaveBody = {
    name: venue.source === 'catalog' ? venue.name : tidy(venue.name, NAME_MAX),
    address: venue.source === 'catalog' ? venue.address || coordinatesText(venue.at) : tidy(venue.address, ADDRESS_MAX) || coordinatesText(venue.at),
    location: pointOf(venue.at),
    category: knownCategory(choices.category),
    circleId: choices.circleId,
    privacy: choices.privacy
  };
  const notes = choices.privateNotes.trim().slice(0, NOTES_MAX);
  if (notes) body.privateNotes = notes;
  if (choices.userRating !== null && Number.isFinite(choices.userRating)) {
    body.userRating = Math.min(10, Math.max(0, Math.round(choices.userRating)));
  }
  if (venue.source === 'catalog' && venue.globalPlaceId) body.globalPlaceId = venue.globalPlaceId;
  if (options.force) body.force = true;
  return body;
}

/** What's missing from a place typed by hand, in words; null when it can be saved. */
export function handProblem(name: string, at: LatLng | null): string | null {
  if (!tidy(name, NAME_MAX)) return 'Give the place a name.';
  if (!at) return 'Tap the map to put a pin where the place is.';
  return null;
}

/**
 * The circle a new save starts on: the one in the link (?circle=) when it is
 * one I can save to, else the one used last, else the first in my order.
 */
export function initialCircle(targets: Circle[], fromLink: string | null | undefined, lastUsed: string | null | undefined): string | null {
  if (fromLink && targets.some((c) => c._id === fromLink)) return fromLink;
  return startingCircle(targets, lastUsed);
}

export interface Duplicate {
  existingPlaceId: string | null;
  /** "Already in Coffee" — or a plainer line when the server didn't name the circle */
  title: string;
  message: string;
}

/**
 * The server said I already saved this place (400 DUPLICATE_PLACE). Some of
 * its checks name the circle, some only send the id: then it's the circle I
 * was saving to (those checks look inside it).
 */
export function duplicateOf(body: Record<string, unknown>, savingToName: string | null): Duplicate | null {
  if (body.code !== 'DUPLICATE_PLACE') return null;
  const named = typeof body.existingCircleName === 'string' && body.existingCircleName ? body.existingCircleName : null;
  const sameCircle = !body.existingCircleId && !named;
  const circleName = named || (sameCircle ? savingToName : null);
  return {
    existingPlaceId: typeof body.existingPlaceId === 'string' ? body.existingPlaceId : null,
    title: circleName ? `Already in ${circleName}` : 'Already saved',
    message: typeof body.message === 'string' && body.message ? body.message : 'You already saved this place.'
  };
}

export interface SaveOutcome {
  /** Waiting for review: saved private until then */
  pending: boolean;
  toast: string;
}

/** What to tell the person once the save went through. */
export function outcomeOf(place: { approvalStatus?: string | null }, circleName: string | null): SaveOutcome {
  if (place.approvalStatus === 'pending') {
    return { pending: true, toast: 'Saved privately. Others can see it once it has been reviewed.' };
  }
  return { pending: false, toast: circleName ? `Saved to ${circleName}` : 'Place saved' };
}

/** The middle of a set of points (median, so one far-off place doesn't pull it), or null. */
export function middleOf(points: LatLng[]): LatLng | null {
  if (points.length === 0) return null;
  const median = (values: number[]) => {
    const sorted = [...values].sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  };
  return { lat: median(points.map((p) => p.lat)), lng: median(points.map((p) => p.lng)) };
}

/** Shortest search worth sending (the server's OpenStreetMap search wants 3). */
export const MIN_VENUE_QUERY = 3;
export const venueQueryOf = (text: string): string => text.replace(/\s+/g, ' ').trim().slice(0, 120);
