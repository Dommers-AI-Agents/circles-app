// The Activity feed: what the people (and stores) I follow did, with
// reactions and comments on each row. Shapes as the server sends them
// (backend/controllers/activityController.js, iOS Models/Activity.swift).
import { ApiError, del, get, post } from './client';

export interface ActivityActor {
  _id: string;
  displayName?: string;
  profilePicture?: string | null;
  /** A store speaking for itself (venue_announcement / venue_offer rows) */
  isPlace?: boolean;
}

export interface ActivityMetadata {
  comment?: string | null;
  placePhoto?: string | null;
  placeAddress?: string | null;
  placeId?: string | null;
  globalPlaceId?: string | null;
  message?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  placeCategory?: string | null;
  videoThumbnail?: string | null;
  contentType?: string | null;
  imageUrl?: string | null;
  recipientName?: string | null;
  workoutDetail?: string | null;
  workoutPlaceName?: string | null;
  runDetail?: string | null;
}

export interface ReactionSummary {
  emoji: string;
  count: number;
}

export interface Activity {
  _id: string;
  /** The server adds types over time: an unknown one must still draw a card */
  type: string;
  actorId: string;
  actor?: ActivityActor | null;
  targetType?: string | null;
  targetId?: string | null;
  targetName?: string | null;
  circleId?: string | null;
  circleName?: string | null;
  metadata?: ActivityMetadata | null;
  timestamp?: string;
  reactionCount?: number;
  commentCount?: number;
  userReaction?: string | null;
  reactionSummary?: ReactionSummary[] | null;
}

export interface FeedPage {
  activities: Activity[];
  hasMore: boolean;
  /** The offset this page was asked for */
  offset: number;
}

export const FEED_PAGE_SIZE = 20;

export const feedPage = (offset: number, signal?: AbortSignal): Promise<FeedPage> =>
  get<{ activities?: Activity[]; hasMore?: boolean }>('/network/activities', { limit: FEED_PAGE_SIZE, offset }, signal)
    .then((r) => ({ activities: r.activities || [], hasMore: r.hasMore === true, offset }));

const reactionsPath = (activityId: string) => `/activities/${encodeURIComponent(activityId)}/reactions`;

/** Puts my reaction on a row; a second call with another emoji swaps it. */
export const react = (activityId: string, emoji: string) => post(reactionsPath(activityId), { emoji });

/** Takes my reaction off. Already gone (404) counts as done. */
export const unreact = (activityId: string) =>
  del(reactionsPath(activityId)).catch((error) => {
    if (error instanceof ApiError && error.status === 404) return undefined;
    throw error;
  });

export interface ActivityComment {
  _id: string;
  userId: string;
  userName?: string;
  userPhoto?: string | null;
  text: string;
  createdAt?: string;
}

const commentsPath = (activityId: string) => `/activities/${encodeURIComponent(activityId)}/comments`;

/** Newest first, as the server sorts them. */
export const activityComments = (activityId: string) =>
  get<{ data?: ActivityComment[] }>(commentsPath(activityId)).then((r) => r.data || []);

export const addActivityComment = (activityId: string, text: string) =>
  post<{ data: ActivityComment }>(commentsPath(activityId), { text }).then((r) => r.data);

export const deleteActivityComment = (activityId: string, commentId: string) =>
  del(`${commentsPath(activityId)}/${encodeURIComponent(commentId)}`);
