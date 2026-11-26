// Rules for the comments and likes on the Place page, and where the page goes
// after a write leaves its own link pointing at nothing. Pure.
import type { PlaceView } from './placeView';

export interface CommentLike {
  userId: string;
  placeId?: string | null;
  parentCommentId?: string | null;
  likes?: string[];
  likesCount?: number;
  user?: { displayName?: string | null } | null;
}

/**
 * May I delete this comment? Its author may, anywhere. Otherwise only the
 * owner of the very save it was written on (the server's rule in
 * services/placeCommentRules.js): having saved the same venue gives no say.
 * `socialId` is the save the request goes through; `iOwnSocial` says it's mine.
 */
export function canDeleteComment(comment: CommentLike, userId: string | undefined, socialId: string | null, iOwnSocial: boolean): boolean {
  if (!userId) return false;
  if (comment.userId === userId) return true;
  return iOwnSocial && !!socialId && comment.placeId === socialId;
}

/** Replies go one level deep: a reply has no Reply button of its own. */
export const canReplyTo = (comment: CommentLike): boolean => !comment.parentCommentId;

export const authorName = (comment: CommentLike): string =>
  (comment.user && typeof comment.user.displayName === 'string' && comment.user.displayName.trim()) || 'Someone';

/** Did I like it? Likes are user ids. */
export const likedBy = (likes: readonly string[] | null | undefined, userId: string | undefined): boolean =>
  !!userId && Array.isArray(likes) && likes.includes(userId);

/** The likes list once my tap lands (the server toggles; this mirrors it at once). */
export function toggledLikes(likes: readonly string[] | null | undefined, userId: string): string[] {
  const list = Array.isArray(likes) ? [...likes] : [];
  return list.includes(userId) ? list.filter((id) => id !== userId) : [...list, userId];
}

/** Is the social save mine? (Then I may also delete comments written on it.) */
export const ownsSocial = (view: Pick<PlaceView, 'mine' | 'socialId'>): boolean =>
  !!view.mine && !!view.socialId && view.mine.id === view.socialId;

/**
 * After I unsave: when the page was opened by my save's own id, that link is
 * dead, so go to the venue (where "Save to a circle" waits) or back. null →
 * stay, just reload (the page was opened by another id that still works).
 */
export function routeAfterUnsave(view: Pick<PlaceView, 'kind' | 'venue'>): string | null {
  if (view.kind !== 'mine') return null;
  return view.venue.globalPlaceId ? `/place/${view.venue.globalPlaceId}` : '';
}

/**
 * After a move. A merge deletes my save in favour of the one already in the
 * target circle, so a page opened by my save's id follows it there.
 */
export function routeAfterMove(view: Pick<PlaceView, 'kind'>, merged: boolean, survivingId: string | null | undefined): string | null {
  if (!merged || view.kind !== 'mine' || !survivingId) return null;
  return `/place/${survivingId}`;
}
