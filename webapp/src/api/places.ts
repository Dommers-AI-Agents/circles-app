// One place: the venue, my save of it, and what people say about it.
//
// A place id in a link is one of three things, and the server has a
// different door for each:
//   - a SAVE id (`places` doc): GET /places/:id. Only this door checks who may
//     see it (403) and it 404s for a venue id.
//   - a VENUE id (`globalPlaces` doc): GET /places/global/:id. The raw venue
//     record plus `representativeSave` (my save, else the oldest one I may see).
//   - my own save of a venue: GET /places/my-save/:venueId (the raw save doc).
// Likes, savers and comments are kept on the venue but their routes only
// accept a SAVE id; follow, the bell and rewards accept either.
import { ApiError, del, get, post, put } from './client';
import type { GeoPoint, OpeningHours, Place, PlacePrivacy, User } from './types';
import { viewFromSave, viewFromVenue, type PlaceView } from '../logic/placeView';
import type { NextReward } from './rewards';

/** addedByUser as the server really sends it (types.ts says {name, photo}). */
export interface AddedBy {
  id?: string;
  displayName?: string;
  profilePicture?: string | null;
  name?: string;
  photo?: string | null;
}

/** A save as the single-place routes send it. */
export type SavedPlace = Omit<Place, 'addedByUser' | 'photos' | 'openingHours'> & {
  addedByUser?: AddedBy | null;
  photos?: (string | { url?: string | null } | null)[];
  openingHours?: HoursRow[] | null;
  googlePlaceId?: string | null;
  followersCount?: number;
  /** Set while the venue waits for review (and kept if it was turned down) */
  privacyBeforeApproval?: string | null;
};

/** `open`/`close` arrive as null (not missing) on a closed day. */
export type HoursRow = Omit<OpeningHours, 'open' | 'close'> & { open?: string | null; close?: string | null };

export interface VenuePhoto { url?: string | null; removedAt?: string | null }

/** The venue record, as GET /places/global/:id sends it. */
export interface GlobalPlace {
  _id: string;
  name?: string;
  address?: string | null;
  location?: GeoPoint | null;
  category?: string;
  description?: string | null;
  googlePlaceId?: string | null;
  photos?: (VenuePhoto | string | null)[];
  coverPhotoUrl?: string | null;
  googleData?: {
    rating?: number | null;
    userRatingsTotal?: number | null;
    priceLevel?: number | null;
    openingHours?: HoursRow[] | null;
    website?: string | null;
    phone?: string | null;
  } | null;
  likes?: string[];
  commentsCount?: number;
  followers?: string[];
  followersCount?: number;
  alertFollowerIds?: string[];
  approvalStatus?: string | null;
}

interface GlobalPlaceResponse {
  data: { globalPlace: GlobalPlace; representativeSave?: SavedPlace | null };
}

const enc = encodeURIComponent;

const fetchSave = (id: string) => get<{ place: SavedPlace }>(`/places/${enc(id)}`).then((r) => r.place);
const fetchVenue = (id: string) => get<GlobalPlaceResponse>(`/places/global/${enc(id)}`).then((r) => r.data);

/** My own save of a venue, or null when I haven't saved it. */
export const mySaveOf = async (globalPlaceId: string): Promise<SavedPlace | null> => {
  try {
    return (await get<{ place: SavedPlace }>(`/places/my-save/${enc(globalPlaceId)}`)).place;
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) return null;
    throw error;
  }
};

/**
 * Whatever kind of id the link carries, one view of the place.
 * Throws ApiError 403 (it's private) or 404 (no such place).
 */
export async function loadPlaceView(id: string, userId: string | undefined): Promise<PlaceView> {
  let save: SavedPlace;
  try {
    save = await fetchSave(id);
  } catch (error) {
    // Not a save id: try it as a venue. A 403 stops here: it IS a save, and
    // it isn't mine to see.
    if (!(error instanceof ApiError) || error.status !== 404) throw error;
    const { globalPlace, representativeSave } = await fetchVenue(id);
    return viewFromVenue(id, globalPlace, representativeSave || null, userId);
  }
  const isMine = !!userId && save.addedBy === userId;
  // GET /places/:id never says whether the venue is waiting for review; the
  // save's held privacy hints at it, the venue record settles it.
  const [mine, venue] = await Promise.all([
    isMine || !save.globalPlaceId ? Promise.resolve(null) : mySaveOf(save.globalPlaceId),
    isMine && save.privacyBeforeApproval && save.globalPlaceId
      ? fetchVenue(save.globalPlaceId).then((r) => r.globalPlace).catch(() => null)
      : Promise.resolve(null)
  ]);
  return viewFromSave(id, save, mine, userId, venue ? venue.approvalStatus || null : undefined);
}

// ---- my save

export interface SaveEdits {
  privateNotes?: string;
  userRating?: number | null;
  privacy?: PlacePrivacy;
  tags?: string[];
}

/** Send only what the person changed (logic/placeChanges). */
export const updateSave = (saveId: string, changes: SaveEdits) =>
  put<{ place: SavedPlace }>(`/places/${enc(saveId)}`, changes).then((r) => r.place);

export interface MoveResult { merged?: boolean; message?: string; place: SavedPlace }
/** `merged: true` → the target circle already held this venue; `place` is THAT save and mine is gone. */
export const moveSave = (saveId: string, targetCircleId: string) =>
  post<MoveResult>(`/places/${enc(saveId)}/move`, { targetCircleId });

/** Unsave: takes it out of my circle. The venue stays for everyone else. */
export const unsave = (saveId: string) => del<{ message: string }>(`/places/${enc(saveId)}`);

export interface NewSave {
  circleId: string;
  globalPlaceId?: string | null;
  googlePlaceId?: string | null;
  name: string;
  address: string;
  /** Required by the server even when it knows the venue */
  location: GeoPoint;
  category: string;
  /** "Save it anyway": skips the server's already-saved check */
  force?: boolean;
}
export const savePlace = (body: NewSave) => post<{ place: SavedPlace }>('/places', body).then((r) => r.place);

// ---- social (all take a SAVE id)

export const toggleLike = (saveId: string) =>
  post<{ liked: boolean; place: { likes?: string[] } }>(`/places/${enc(saveId)}/like`);

export interface Saver {
  _id: string;
  displayName?: string;
  profilePicture?: string | null;
  bio?: string | null;
  connectionStatus?: string;
}
/** `totalCount` also counts savers I'm not allowed to see. */
export const placeSavers = (saveId: string) =>
  get<{ savers: Saver[]; count: number; totalCount?: number }>(`/places/${enc(saveId)}/savers`);

export interface PlaceComment {
  _id: string;
  placeId: string;
  userId: string;
  text: string;
  likes?: string[];
  likesCount?: number;
  replyCount?: number;
  parentCommentId?: string | null;
  createdAt?: string;
  editedAt?: string | null;
  isVenueOwner?: boolean;
  user?: Pick<User, '_id' | 'displayName' | 'profilePicture'> | null;
}
/** Top-level comments, newest first. */
export const placeComments = (saveId: string) =>
  get<{ comments: PlaceComment[] }>(`/places/${enc(saveId)}/comments`).then((r) => r.comments || []);
export const addComment = (saveId: string, text: string) =>
  post<{ data: PlaceComment }>(`/places/${enc(saveId)}/comments`, { text }).then((r) => r.data);
export const deleteComment = (saveId: string, commentId: string) =>
  del<{ message: string }>(`/places/${enc(saveId)}/comments/${enc(commentId)}`);
export const likeComment = (saveId: string, commentId: string) =>
  post<{ liked: boolean; likesCount: number }>(`/places/${enc(saveId)}/comments/${enc(commentId)}/like`);
export const commentReplies = (saveId: string, commentId: string) =>
  get<{ comments: PlaceComment[] }>(`/places/${enc(saveId)}/comments/${enc(commentId)}/replies`).then((r) => r.comments || []);
export const addReply = (saveId: string, commentId: string, text: string) =>
  post<{ data: PlaceComment }>(`/places/${enc(saveId)}/comments/${enc(commentId)}/replies`, { text }).then((r) => r.data);

// ---- the store (these take a save id or a venue id)

export const followPlace = (id: string) => post<{ following: boolean; followersCount: number }>(`/places/${enc(id)}/follow`);
export const unfollowPlace = (id: string) => del<{ following: boolean; followersCount: number }>(`/places/${enc(id)}/follow`);
/** The bell. The server answers 409 unless I already follow the place. */
export const setPlaceAlerts = (id: string, on: boolean) =>
  on ? post<{ alertsOn: boolean }>(`/places/${enc(id)}/follow/alerts`) : del<{ alertsOn: boolean }>(`/places/${enc(id)}/follow/alerts`);

export interface StoreRewards {
  venue: { venueId: string; venueName?: string; placeName?: string; earnRate?: number | null; genericJoin?: boolean } | null;
  rewardsLive?: boolean;
  offers?: { offerId: string; title: string; pointsCost: number }[];
  venueBalance?: number;
  nextReward?: NextReward | null;
}
/** `venue: null` is the usual answer: most places aren't stores on FavCircles. */
export const storeRewards = (id: string) =>
  get<{ data: StoreRewards }>(`/rewards/venues/by-place/${enc(id)}`).then((r) => r.data);
