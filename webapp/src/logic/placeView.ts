// One shape for the Place page, whichever door the place came through: a
// save (mine or someone else's) or the bare venue record. Pure.
import type { GeoPoint, PlacePrivacy } from '../api/types';
import type { AddedBy, GlobalPlace, HoursRow, SavedPlace } from '../api/places';

export interface Venue {
  /** null only for an old save the server could not link to a venue */
  globalPlaceId: string | null;
  googlePlaceId: string | null;
  name: string;
  address: string;
  location: GeoPoint | null;
  category: string;
  description: string;
  photos: string[];
  rating: number | null;
  ratingCount: number | null;
  priceLevel: number | null;
  hours: HoursRow[];
  phone: string;
  website: string;
}

/** What I keep on my own save. Never filled from anyone else's. */
export interface MySave {
  id: string;
  circleId: string | null;
  privateNotes: string;
  userRating: number | null;
  privacy: PlacePrivacy;
  tags: string[];
}

export interface PlaceView {
  /** The id in the link */
  routeId: string;
  /** mine: my own save · theirs: someone else's save · venue: opened by its venue id */
  kind: 'mine' | 'theirs' | 'venue';
  venue: Venue;
  mine: MySave | null;
  /** Whose save this is, when it is someone else's */
  savedBy: { id: string; name: string; photo: string | null } | null;
  /** The save id that likes, savers and comments go through; null → read-only */
  socialId: string | null;
  /** Follow, the bell and rewards take either kind of id */
  storeId: string;
  /** What a shared link carries: the venue when there is one */
  shareId: string;
  likes: string[];
  commentsCount: number;
  isFollowing: boolean;
  followAlerts: boolean;
  followersCount: number;
  /** Waiting for review: only the people who saved it see it */
  pending: boolean;
}

const text = (value: unknown): string => (typeof value === 'string' ? value.trim() : '');
const num = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? value : null);

/** Photo URLs, https only, each once. Accepts plain URLs and `{url}` records. */
export function photoUrls(photos: unknown, cover?: string | null): string[] {
  const urls: string[] = [];
  const add = (value: unknown) => {
    const url = typeof value === 'string' ? value : value && typeof value === 'object' ? (value as { url?: unknown; removedAt?: unknown }) : null;
    if (url && typeof url === 'object') {
      if (url.removedAt) return;
      add(url.url);
      return;
    }
    if (typeof url === 'string' && /^https:\/\//i.test(url) && !urls.includes(url)) urls.push(url);
  };
  add(cover);
  if (Array.isArray(photos)) photos.forEach(add);
  return urls;
}

const hoursOf = (rows: unknown): HoursRow[] =>
  Array.isArray(rows) ? rows.filter((row): row is HoursRow => !!row && typeof row === 'object' && typeof (row as HoursRow).day === 'number') : [];

export function venueOfSave(save: SavedPlace): Venue {
  return {
    globalPlaceId: save.globalPlaceId || null,
    googlePlaceId: save.googlePlaceId || null,
    name: text(save.name) || 'A place',
    address: text(save.address),
    location: save.location || null,
    category: save.category || 'other',
    description: text(save.description),
    photos: photoUrls(save.photos),
    rating: num(save.rating),
    ratingCount: num(save.userRatingsTotal),
    priceLevel: num(save.priceLevel),
    hours: hoursOf(save.openingHours),
    phone: text(save.phone),
    website: text(save.website),
  };
}

/** The venue record keeps rating, hours and contact details under `googleData`. */
export function venueOfGlobal(place: GlobalPlace): Venue {
  const google = place.googleData || {};
  return {
    globalPlaceId: place._id,
    googlePlaceId: place.googlePlaceId || null,
    name: text(place.name) || 'A place',
    address: text(place.address),
    location: place.location || null,
    category: place.category || 'other',
    description: text(place.description),
    photos: photoUrls(place.photos, place.coverPhotoUrl),
    rating: num(google.rating),
    ratingCount: num(google.userRatingsTotal),
    priceLevel: num(google.priceLevel),
    hours: hoursOf(google.openingHours),
    phone: text(google.phone),
    website: text(google.website),
  };
}

export function mySaveOf(save: SavedPlace | null | undefined, userId: string | undefined): MySave | null {
  // Notes, rating and privacy are read only from a save that is really mine:
  // the venue route hands back other people's saves with their notes still on
  if (!save || !userId || save.addedBy !== userId) return null;
  return {
    id: save._id,
    circleId: save.circleId || null,
    privateNotes: typeof save.privateNotes === 'string' ? save.privateNotes : '',
    userRating: num(save.userRating),
    privacy: save.privacy || 'followCircle',
    tags: Array.isArray(save.tags) ? save.tags.filter((tag) => typeof tag === 'string') : [],
  };
}

function saverOf(save: SavedPlace): PlaceView['savedBy'] {
  const by: AddedBy = save.addedByUser || {};
  const id = by.id || save.addedBy || '';
  if (!id) return null;
  return { id, name: text(by.displayName) || text(by.name) || 'Someone', photo: by.profilePicture || by.photo || null };
}

/**
 * Opened by a save id. `mine` is my own save of the same venue when the one
 * I'm looking at is someone else's. `approvalStatus` is the venue's, when the
 * caller looked it up (undefined → go by what the save says).
 */
export function viewFromSave(
  routeId: string, save: SavedPlace, mine: SavedPlace | null, userId: string | undefined, approvalStatus?: string | null
): PlaceView {
  const own = mySaveOf(save, userId);
  const venue = venueOfSave(save);
  const likes = Array.isArray(save.likes) ? save.likes : [];
  return {
    routeId,
    kind: own ? 'mine' : 'theirs',
    venue,
    mine: own || mySaveOf(mine, userId),
    savedBy: own ? null : saverOf(save),
    socialId: save._id,
    storeId: venue.globalPlaceId || save._id,
    shareId: venue.globalPlaceId || save._id,
    likes,
    commentsCount: num(save.commentsCount) || 0,
    isFollowing: save.isFollowing === true,
    followAlerts: save.followAlerts === true,
    followersCount: num(save.followersCount) || 0,
    pending: approvalStatus !== undefined ? approvalStatus === 'pending' : save.approvalStatus === 'pending',
  };
}

/** Opened by a venue id. `representative` is my save, else the oldest save I may see, else null. */
export function viewFromVenue(
  routeId: string, place: GlobalPlace, representative: SavedPlace | null, userId: string | undefined
): PlaceView {
  const venue = venueOfGlobal(place);
  const own = mySaveOf(representative, userId);
  const followers = Array.isArray(place.followers) ? place.followers : [];
  const alerts = Array.isArray(place.alertFollowerIds) ? place.alertFollowerIds : [];
  const likes = Array.isArray(place.likes) ? place.likes : [];
  // A save's own photos the venue library doesn't hold yet still show
  if (representative) photoUrls(representative.photos).forEach((url) => { if (!venue.photos.includes(url)) venue.photos.push(url); });
  return {
    routeId,
    kind: 'venue',
    venue,
    mine: own,
    savedBy: representative && !own ? saverOf(representative) : null,
    socialId: representative ? representative._id : null,
    storeId: place._id,
    shareId: place._id,
    likes,
    commentsCount: num(place.commentsCount) || 0,
    isFollowing: !!userId && followers.includes(userId),
    followAlerts: !!userId && followers.includes(userId) && alerts.includes(userId),
    followersCount: num(place.followersCount) ?? followers.length,
    pending: place.approvalStatus === 'pending',
  };
}

/** "$$" for 2; nothing when the venue has no price level (0 is "free", which Google rarely means). */
export const priceText = (level: number | null): string => (level && level >= 1 && level <= 4 ? '$'.repeat(Math.round(level)) : '');

/** "4.5 (1,203)" */
export function ratingText(rating: number | null, count: number | null): string {
  if (rating === null || rating <= 0) return '';
  return count && count > 0 ? `${rating.toFixed(1)} (${count.toLocaleString('en-US')})` : rating.toFixed(1);
}

/** A website the page may link to: http(s) only, with a scheme added to a bare host. */
export function websiteHref(website: string): string | null {
  const value = website.trim();
  if (!value) return null;
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(value) ? value : `https://${value}`;
  try {
    const url = new URL(withScheme);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : null;
  } catch {
    return null;
  }
}

/** "tel:+17045551234" from "(704) 555-1234"; null when there are no digits to dial. */
export function telHref(phone: string): string | null {
  const digits = phone.replace(/[^\d+]/g, '').replace(/(?!^)\+/g, '');
  return digits.replace(/\D/g, '').length >= 3 ? `tel:${digits}` : null;
}

export const directionsHref = (lat: number, lng: number): string =>
  `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
