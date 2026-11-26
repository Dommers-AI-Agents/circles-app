// The API's shapes, as the server sends them (see backend/models and the
// iOS Models/). Only the fields the web app reads.

export type Privacy = 'public' | 'myNetwork' | 'innerCircle' | 'private';
export type PlacePrivacy = Privacy | 'followCircle';

export interface User {
  _id: string;
  id?: string;
  email?: string;
  displayName: string;
  firstName?: string | null;
  lastName?: string | null;
  profilePicture?: string | null;
  bio?: string | null;
  location?: string | null;
  zipcode?: string | null;
  followersCount?: number;
  followingCount?: number;
  connectionsCount?: number;
  placesCount?: number;
  circlesCount?: number;
  profilePrivate?: boolean;
  isFollowing?: boolean;
  followsYou?: boolean;
  followRequested?: boolean;
  connectionStatus?: string | null;
  connectionDirection?: string | null;
  connectionId?: string | null;
  suggestionReason?: string | null;
  isBusiness?: boolean;
}

export interface GeoPoint {
  type: 'Point';
  /** [longitude, latitude] — GeoJSON order */
  coordinates: [number, number];
}

export interface OpeningHours {
  day: number;
  open?: string;
  close?: string;
  isClosed?: boolean;
}

export interface Place {
  _id: string;
  id?: string;
  globalPlaceId?: string | null;
  name: string;
  description?: string | null;
  address?: string | null;
  location?: GeoPoint | null;
  photos?: string[];
  category?: string;
  rating?: number | null;
  userRatingsTotal?: number | null;
  priceLevel?: number | null;
  openingHours?: OpeningHours[] | null;
  website?: string | null;
  phone?: string | null;
  privateNotes?: string | null;
  userRating?: number | null;
  tags?: string[];
  circleId?: string | null;
  circleName?: string;
  addedBy?: string;
  addedByUser?: { name?: string; photo?: string | null } | null;
  privacy?: PlacePrivacy;
  likes?: string[];
  likesCount?: number;
  commentsCount?: number;
  isFollowing?: boolean;
  followAlerts?: boolean;
  approvalStatus?: string | null;
  isNew?: boolean;
  createdAt?: string;
}

export interface Circle {
  _id: string;
  id?: string;
  name: string;
  description?: string | null;
  coverImage?: string | null;
  owner: string;
  ownerDetails?: User | null;
  places?: string[];
  placesWithDetails?: Place[];
  placesCount?: number;
  privacy: Privacy;
  showOnMap?: boolean;
  category?: string;
  isSystemCircle?: boolean;
  isCheckInCircle?: boolean;
  isFollowedPlacesCircle?: boolean;
  locked?: boolean;
  lockedReason?: 'connect' | 'follow';
  hasNewPlaces?: boolean;
  newPlacesCount?: number;
}

export interface SessionResponse {
  success: boolean;
  token: string;
  expiresIn?: number;
  newAccount?: boolean;
  user: User;
}
