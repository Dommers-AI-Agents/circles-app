// People: profiles, follows, connections, blocks, discovery, my settings,
// and the app-wide search. Shapes are read from the backend controllers
// (users/followController, connectionController, blockController,
// userDiscoveryController, deviceTokenController, networkPlacesController).
import { del, get, post, put } from './client';
import type { Circle, Place, User } from './types';
import type { NotificationPreferences } from '../logic/notificationSwitches';

/** A person as any of the people lists sends them: some use `id`, some `_id`. */
type PersonExtras = { distance?: number | null; discoveryType?: string; mutualConnectionNames?: string[] | null };
export type RawPerson = Omit<User, '_id'> & { _id?: string; id?: string } & PersonExtras;
export type Person = User & PersonExtras;

export const personOf = (raw: RawPerson): Person => ({ ...raw, _id: String(raw._id || raw.id || '') });
const peopleOf = (list: RawPerson[] | undefined): Person[] => (list || []).map(personOf).filter((p) => p._id);

const uid = (id: string) => encodeURIComponent(id);

// ---- a profile
export interface Profile {
  user: Person;
  /** In the owner's own order; locked ones carry `locked` + `lockedReason`. */
  circles: Circle[];
}
export const profile = (userId: string) =>
  get<{ data: { user: RawPerson; circles: Circle[] } }>(`/network/user-circles/${uid(userId)}`, { includeLocked: 1 })
    .then((r): Profile => ({ user: personOf(r.data.user), circles: r.data.circles || [] }));

// ---- follow
export interface FollowResult {
  /** A private profile: the follow waits for their yes */
  requested?: boolean;
  alreadyFollowing?: boolean;
  message?: string;
}
export const follow = (userId: string) => post<FollowResult>(`/users/${uid(userId)}/follow`);

export interface UnfollowResult {
  /** I had only asked to follow: the request was taken back */
  requestCancelled?: boolean;
  message?: string;
}
/** 409 `code: 'connected'` when we're connected: disconnecting is the way to stop following. */
export const unfollow = (userId: string) => post<UnfollowResult>(`/users/${uid(userId)}/unfollow`);

export const followers = (userId: string) =>
  get<{ followers: RawPerson[] }>(`/users/${uid(userId)}/followers`).then((r) => peopleOf(r.followers));
export const following = (userId: string) =>
  get<{ following: RawPerson[] }>(`/users/${uid(userId)}/following`).then((r) => peopleOf(r.following));

// ---- follow requests (my profile is private)
export interface FollowRequest {
  requesterId: string;
  user: Person;
  createdAt?: string;
}
export const followRequests = () =>
  get<{ requests: { requesterId: string; user?: RawPerson; createdAt?: string }[] }>('/users/me/follow-requests')
    .then((r): FollowRequest[] => (r.requests || []).map((request) => ({
      requesterId: request.requesterId,
      createdAt: request.createdAt,
      user: personOf({ displayName: 'Someone', ...(request.user || {}), _id: request.requesterId })
    })));
export const acceptFollowRequest = (requesterId: string) => post(`/users/me/follow-requests/${uid(requesterId)}/accept`);
export const declineFollowRequest = (requesterId: string) => post(`/users/me/follow-requests/${uid(requesterId)}/decline`);

// ---- connections
export interface Connection {
  _id?: string;
  id?: string;
  /** Who asked */
  userId: string;
  /** Who was asked */
  connectedUserId: string;
  status: 'pending' | 'accepted' | 'blocked' | string;
  connectedUser?: RawPerson;
  createdAt?: string;
}
export const connections = () => get<{ connections: Connection[] }>('/connections').then((r) => r.connections || []);

export interface InviteResult {
  data: Connection;
  alreadyPending?: boolean;
  message?: string;
}
/** 201 for a new invitation; 200 when one is already waiting or we're already connected. */
export const invite = (targetUserId: string) => post<InviteResult>('/connections/invite', { targetUserId });
export const acceptConnection = (connectionId: string) => post<{ data: Connection }>(`/connections/${uid(connectionId)}/accept`);
/** Turns down an invitation sent to me, or takes back one I sent. */
export const declineConnection = (connectionId: string) => del<{ message: string }>(`/connections/${uid(connectionId)}/decline`);
/** Disconnect: also stops my follow of them. */
export const removeConnection = (connectionId: string) => del<{ message: string }>(`/connections/${uid(connectionId)}`);

// ---- blocks
export interface Block {
  id: string;
  blockedUserId: string;
  blockedUser?: RawPerson;
  createdAt?: string;
}
export const blocks = () => get<{ blocks: Block[] }>('/blocks').then((r) => r.blocks || []);
export const blockStatus = (userId: string) =>
  get<{ isBlockedByMe: boolean; hasBlockedMe: boolean }>(`/blocks/check/${uid(userId)}`);
export const block = (userId: string) => post(`/blocks/user/${uid(userId)}`);
export const unblock = (userId: string) => del(`/blocks/user/${uid(userId)}`);

// ---- messages (the conversation screen is /messages/<id>)
export const directConversation = (userId: string) =>
  post<{ conversation: { _id?: string; id?: string } }>(`/messages/conversations/direct/${uid(userId)}`)
    .then((r) => String(r.conversation._id || r.conversation.id || ''));

// ---- finding people
export type DiscoverType = 'nearby' | 'followsYou' | 'friendsOfFriends' | 'popular';
export interface DiscoverPage {
  users: Person[];
  hasMore: boolean;
}
export const discover = (type: DiscoverType, options: { limit: number; offset: number; lat?: number; lng?: number }) =>
  get<{ users: RawPerson[]; hasMore?: boolean }>('/users/contacts/discover', { type, ...options })
    .then((r): DiscoverPage => ({ users: peopleOf(r.users), hasMore: r.hasMore === true }));

export const searchPeople = (query: string, signal?: AbortSignal) =>
  get<{ users: RawPerson[] }>('/users/search', { query }, signal).then((r) => peopleOf(r.users));

// ---- my settings
export const setProfilePrivacy = (isPrivate: boolean) =>
  put<{ profilePrivate: boolean; acceptedRequests: number }>('/users/me/profile-privacy', { private: isPrivate });

/** Saves the switches given (the server merges them into the saved ones) and answers with every saved preference. */
export const saveNotificationPreferences = (changes: NotificationPreferences) =>
  put<{ user: { notificationPreferences?: NotificationPreferences | null } }>('/users/notification-preferences', { notificationPreferences: changes })
    .then((r): NotificationPreferences => r.user.notificationPreferences || {});

/**
 * My saved switches. No GET sends them; PUT /users/me with nothing to change
 * writes only its `updatedAt` and answers with my own profile, which carries
 * them. Never read them by saving an empty set of switches: the server stores
 * `{}` over the saved map and every switch is lost.
 */
export const myNotificationPreferences = () =>
  put<{ user?: { notificationPreferences?: NotificationPreferences | null } }>('/users/me', {})
    .then((r): NotificationPreferences => (r.user && r.user.notificationPreferences) || {});

/** Deletes my account and everything I made. There is no undo. */
export const deleteMyAccount = () => del<{ message: string }>('/users/me');

// ---- search
export type MyPlace = Place & { circleName?: string; notes?: string | null; publicNotes?: string | null };
export const myPlaces = () => get<{ data: MyPlace[] }>('/places/my-places').then((r) => r.data || []);

export type FriendPlace = Omit<Place, 'addedByUser'> & {
  addedByUser?: { id?: string; displayName?: string; name?: string; profilePicture?: string | null; photo?: string | null } | null;
};
export const searchFriendsPlaces = (query: string, origin: { lat: number; lng: number } | null, signal?: AbortSignal) =>
  get<{ places: FriendPlace[] }>('/network/places/search', { query, lat: origin?.lat, lng: origin?.lng, limit: 20 }, signal)
    .then((r) => r.places || []);

/** A venue in the FavCircles catalog (a globalPlaces record, not anyone's save). */
export interface CatalogPlace {
  _id: string;
  id?: string;
  name: string;
  address?: string | null;
  category?: string;
  coverPhotoUrl?: string | null;
  photos?: ({ url?: string } | string)[];
  location?: Place['location'];
}
export const searchCatalog = (query: string, origin: { lat: number; lng: number }, signal?: AbortSignal) =>
  get<{ data: CatalogPlace[] }>('/places/global/search', { query, lat: origin.lat, lng: origin.lng, radius: 80, limit: 20 }, signal)
    .then((r) => r.data || []);
