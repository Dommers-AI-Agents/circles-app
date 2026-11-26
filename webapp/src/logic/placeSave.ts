// Rules for my own save of a place: what an edit sends, and which circle a
// new save goes to. Pure.
import type { Circle, PlacePrivacy } from '../api/types';
import type { SaveEdits } from '../api/places';
import type { MySave } from './placeView';

/** The key the last circle I saved to is remembered under (Add Place shares it). */
export const LAST_CIRCLE_KEY = 'fc.lastCircle';

export interface SaveForm {
  privateNotes: string;
  userRating: number | null;
  privacy: PlacePrivacy;
  tags: string[];
}

export const formOf = (save: MySave): SaveForm => ({
  privateNotes: save.privateNotes,
  userRating: save.userRating,
  privacy: save.privacy || 'followCircle',
  tags: save.tags
});

/** "date night, Patio ,patio" → ["date night", "Patio"]: trimmed, no blanks, no repeats. */
export function tagsOf(text: string): string[] {
  const tags: string[] = [];
  text.split(',').forEach((part) => {
    const tag = part.replace(/\s+/g, ' ').trim().slice(0, 40);
    if (tag && !tags.some((t) => t.toLowerCase() === tag.toLowerCase())) tags.push(tag);
  });
  return tags.slice(0, 20);
}

const clampRating = (rating: number | null): number | null =>
  rating === null || !Number.isFinite(rating) ? null : Math.min(10, Math.max(0, Math.round(rating)));

/**
 * Only the fields the person changed. A privacy they did not touch is never
 * sent, so an Inner Circle place (or one that follows its circle) stays as it is.
 */
export function saveChanges(before: MySave, after: SaveForm): SaveEdits {
  const changes: SaveEdits = {};
  const notes = after.privateNotes.trim();
  if (notes !== before.privateNotes.trim()) changes.privateNotes = notes;
  const rating = clampRating(after.userRating);
  if (rating !== clampRating(before.userRating)) changes.userRating = rating;
  if (after.privacy !== (before.privacy || 'followCircle')) changes.privacy = after.privacy;
  if (after.tags.length !== before.tags.length || after.tags.some((tag, index) => tag !== before.tags[index])) changes.tags = after.tags;
  return changes;
}

/** Circles a place can be saved or moved into: my own, minus the ones the app fills itself. */
export function saveTargets(circles: Circle[], userId: string | undefined): Circle[] {
  return circles.filter((circle) => (!userId || circle.owner === userId)
    && !circle.locked && !circle.isCheckInCircle && !circle.isFollowedPlacesCircle);
}

/** The circle a save starts on: the one used last if it is still there, else the first in my order. */
export function startingCircle(targets: Circle[], lastUsedId: string | null | undefined): string | null {
  if (lastUsedId && targets.some((circle) => circle._id === lastUsedId)) return lastUsedId;
  return targets.length > 0 ? targets[0]._id : null;
}

/** 0–10 in words, for the picker's caption. */
export function ratingWord(rating: number | null): string {
  if (rating === null) return 'Not rated';
  if (rating >= 9) return 'A favorite';
  if (rating >= 7) return 'Really good';
  if (rating >= 5) return 'Good';
  if (rating >= 3) return 'Just okay';
  return 'Not for me';
}
