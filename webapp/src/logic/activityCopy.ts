// What one Activity row says, shows and opens. Mirrors the iOS app:
// Models/Activity.swift (formattedDescription, groupSummary),
// Logic/ActivityRowStyle.swift (the picture, chip and poster of each card)
// and HomeActivityFeedViewController.openActivity (where a tap goes).
// Every row is a card with a picture: the photo, else a map of the pin,
// else a poster. A type this build doesn't know still gets a whole card.
import type { Activity, ActivityMetadata } from '../api/feed';
import { categoryOf } from './labels';

export type Tint = 'brand' | 'like' | 'comment' | 'circle' | 'workout' | 'run' | 'mail' | 'people' | 'store';

/** One thing the card can show; the card tries them in order (a photo that fails to load falls to the next). */
export type Picture =
  | { kind: 'photo'; url: string }
  | { kind: 'map'; lat: number; lng: number };

export interface Poster {
  mark: string;
  title: string;
  detail: string | null;
  tint: Tint;
}

export interface ActivityCardCopy {
  actorName: string;
  /** Where the avatar and name go */
  actorPath: string;
  /** Follows the actor's name: "saved STIR to Date Night" */
  sentence: string;
  /** The words of a comment or a check-in note, shown quoted */
  quote: string | null;
  /** The short label on the picture: "Saved to Date Night", "Checked in" */
  chip: string | null;
  /** In the order to try; when empty or all fail, the poster is the picture */
  pictures: Picture[];
  poster: Poster;
  /** Where a tap on the card goes. Never empty: at worst the actor. */
  target: string;
}

const text = (value: unknown): string | null => {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
};

const enc = encodeURIComponent;
const placePath = (id: string) => `/place/${enc(id)}`;
const circlePath = (id: string) => `/circle/${enc(id)}`;
const userPath = (id: string) => `/user/${enc(id)}`;

const LIKES = ['place_liked', 'global_place_liked', 'video_liked', 'comment_liked', 'circle_liked', 'reaction_added'];
const COMMENTS = ['place_commented', 'comment_added', 'circle_commented'];
const CIRCLES = ['circle_created', 'circle_liked', 'circle_commented'];
const MAIL = ['postcard_sent', 'postcard_mailed', 'fridgemail_sent'];
const PEOPLE = ['profile_updated', 'user_activity', 'suggestion_sent', 'suggestion_accepted'];
const STORE = ['venue_announcement', 'venue_offer'];

export function tintOf(type: string): Tint {
  if (LIKES.includes(type)) return 'like';
  if (COMMENTS.includes(type)) return 'comment';
  if (type === 'circle_created') return 'circle';
  if (type === 'workout_shared') return 'workout';
  if (type === 'run_shared') return 'run';
  if (MAIL.includes(type)) return 'mail';
  if (PEOPLE.includes(type)) return 'people';
  if (STORE.includes(type)) return 'store';
  return 'brand';
}

/** The pin of a row, when it carries a real one (0,0 and out-of-range are "none"). */
export function pinOf(metadata: ActivityMetadata | null | undefined): { lat: number; lng: number } | null {
  const lat = metadata?.latitude;
  const lng = metadata?.longitude;
  if (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if ((lat === 0 && lng === 0) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

/** What the row is about, with a fallback so no sentence ever reads "liked ." */
function nameOf(activity: Activity): string {
  const name = text(activity.targetName);
  if (name) return name;
  if (CIRCLES.includes(activity.type) || activity.targetType === 'circle') return 'a circle';
  if (activity.type.startsWith('video_')) return 'a moment';
  if (MAIL.includes(activity.type)) return text(activity.metadata?.recipientName) || 'someone';
  return 'a place';
}

export function sentenceOf(activity: Activity): string {
  const name = nameOf(activity);
  const meta = activity.metadata;
  switch (activity.type) {
    case 'place_added': return `saved ${name} to ${text(activity.circleName) || 'a circle'}`;
    case 'place_liked': return `liked ${name}`;
    case 'place_commented': return `commented on ${name}`;
    case 'circle_created': return `created a new circle ${name}`;
    // Older rows stamped the name as "Comment on <place>"
    case 'comment_liked': return `liked a comment on ${name.startsWith('Comment on ') ? name.slice('Comment on '.length) : name}`;
    case 'check_in': return `checked in at ${name}`;
    // Photo moments ride the video pipeline; contentType tells them apart
    case 'video_uploaded': return meta?.contentType === 'photo' ? `shared a photo at ${name}` : `uploaded a video at ${name}`;
    case 'photo_uploaded': return `uploaded a photo at ${name}`;
    case 'place_discovered': return `discovered ${name}`;
    case 'global_place_liked': return `liked a photo at ${name}`;
    case 'video_liked': return `liked ${name}`;
    case 'comment_added': return `commented on ${name}`;
    case 'circle_liked': return `liked the circle ${name}`;
    case 'circle_commented': return `commented on the circle ${name}`;
    case 'suggestion_sent': return `suggested ${name}`;
    case 'suggestion_accepted': return `accepted a suggestion for ${name}`;
    case 'profile_updated': return 'updated their profile';
    case 'user_activity': return 'was active';
    case 'reaction_added': return `reacted to ${name}`;
    case 'venue_announcement': return text(meta?.message) ? `posted an announcement: ${text(meta?.message)}` : 'posted an announcement';
    case 'venue_offer': return text(meta?.message) ? `added a new offer: ${text(meta?.message)}` : 'added a new offer';
    case 'workout_shared': return `finished a workout: ${name}`;
    case 'run_shared': return `went for a run 🏃 ${text(meta?.runDetail) || ''}`.trim();
    case 'postcard_sent': return `sent a postcard to ${name}`;
    case 'postcard_mailed': return `mailed a printed postcard to ${name}`;
    case 'fridgemail_sent': return `mailed Fridge Mail to ${name}`;
    default: return 'shared an update';
  }
}

function quoteOf(activity: Activity): string | null {
  if (activity.type === 'check_in') return text(activity.metadata?.message);
  if ([...COMMENTS, 'comment_liked'].includes(activity.type)) return text(activity.metadata?.comment);
  return null;
}

function chipOf(activity: Activity): string | null {
  const meta = activity.metadata;
  switch (activity.type) {
    case 'place_added': return text(activity.circleName) ? `Saved to ${text(activity.circleName)}` : 'Saved';
    case 'check_in': return 'Checked in';
    case 'place_liked': return '♥ Liked';
    case 'global_place_liked': return '♥ Liked this photo';
    case 'video_liked': return '♥ Liked this moment';
    case 'comment_liked': return '♥ Liked a comment';
    case 'circle_liked': return '♥ Liked this circle';
    case 'place_commented': case 'comment_added': case 'circle_commented': return '💬 Commented';
    case 'circle_created': return 'New circle';
    case 'venue_announcement': return '📣 Announcement';
    case 'venue_offer': return '🎁 New offer';
    case 'photo_uploaded': return 'Photo';
    case 'video_uploaded': return meta?.contentType === 'photo' ? 'Photo' : 'Moment';
    case 'place_discovered': return 'Discovered';
    case 'suggestion_sent': return 'Suggested';
    case 'suggestion_accepted': return 'Accepted a suggestion';
    case 'reaction_added': return 'Reacted';
    case 'workout_shared': return '🏋️ Workout';
    case 'run_shared': return text(meta?.runDetail) ? `🏃 ${text(meta?.runDetail)}` : '🏃 Run';
    case 'postcard_sent': return 'Postcard';
    case 'postcard_mailed': return 'Printed postcard';
    case 'fridgemail_sent': return 'Fridge Mail';
    default: return null;
  }
}

const TYPE_MARKS: Record<string, string> = {
  place_added: '📍', place_discovered: '✨', check_in: '📍', photo_uploaded: '📷', video_uploaded: '🎬',
  place_liked: '❤️', global_place_liked: '❤️', video_liked: '❤️', comment_liked: '❤️', circle_liked: '❤️',
  place_commented: '💬', comment_added: '💬', circle_commented: '💬', circle_created: '⭕',
  suggestion_sent: '💡', suggestion_accepted: '✅', reaction_added: '👍', profile_updated: '🙂',
  venue_announcement: '📣', venue_offer: '🎁', workout_shared: '🏋️', run_shared: '🏃',
  postcard_sent: '✉️', postcard_mailed: '✉️', fridgemail_sent: '🖼️'
};

const capitalized = (value: string) => value.charAt(0).toUpperCase() + value.slice(1);

/** The drawn card for a row with no photo and no pin: the place's category mark (or the kind's), the name in large type. */
export function posterOf(activity: Activity): Poster {
  const meta = activity.metadata;
  const type = activity.type;
  const tint = tintOf(type);
  const name = nameOf(activity);
  // A place row wears its category's mark; everything else the mark of what happened
  const category = text(meta?.placeCategory);
  const mark = category && !CIRCLES.includes(type) ? categoryOf(category).mark : TYPE_MARKS[type] || '✨';
  switch (type) {
    case 'check_in': return { mark, title: name, detail: text(meta?.placeAddress), tint };
    case 'workout_shared':
      return { mark, title: name, detail: [text(meta?.workoutDetail), text(meta?.workoutPlaceName)].filter(Boolean).join(' · ') || null, tint };
    case 'run_shared': return { mark, title: 'Went for a run', detail: text(meta?.runDetail), tint };
    case 'postcard_sent': case 'postcard_mailed': case 'fridgemail_sent': return { mark, title: `To ${name}`, detail: null, tint };
    case 'venue_announcement': case 'venue_offer':
      return text(meta?.message) ? { mark, title: text(meta?.message) as string, detail: name, tint } : { mark, title: name, detail: null, tint };
    case 'profile_updated': return { mark, title: 'Updated their profile', detail: null, tint };
    default:
      if (TYPE_MARKS[type]) return { mark, title: name, detail: text(meta?.placeAddress), tint };
      // user_activity and types this build doesn't know
      return { mark, title: text(activity.targetName) || capitalized(sentenceOf(activity)), detail: null, tint };
  }
}

/** The pictures a row carries, best first, then its pin. */
export function picturesOf(activity: Activity): Picture[] {
  const meta = activity.metadata;
  const moment = activity.type === 'video_uploaded' || activity.type === 'video_liked';
  const urls = moment
    ? [text(meta?.videoThumbnail), text(meta?.placePhoto), text(meta?.imageUrl)]
    : MAIL.includes(activity.type)
      ? [text(meta?.imageUrl), text(meta?.placePhoto)]
      : [text(meta?.placePhoto), text(meta?.videoThumbnail), text(meta?.imageUrl)];
  const pictures: Picture[] = [];
  urls.forEach((url) => {
    if (url && /^https?:\/\//i.test(url) && !pictures.some((p) => p.kind === 'photo' && p.url === url)) pictures.push({ kind: 'photo', url });
  });
  const pin = pinOf(meta);
  if (pin) pictures.push({ kind: 'map', ...pin });
  return pictures;
}

export function actorPathOf(activity: Activity): string {
  const actor = activity.actor;
  const id = text(actor?._id) || text(activity.actorId) || '';
  if (actor?.isPlace || id.startsWith('place_')) {
    // A store's own rows: targetId is the venue; the actor id is "place_<venue>"
    const venue = STORE.includes(activity.type) ? text(activity.targetId) : null;
    return placePath(venue || id.replace(/^place_/, ''));
  }
  return id ? userPath(id) : '/people';
}

/** Where a tap on the card goes, per type: ids mean different things per type (a photo like's targetId is the photo). */
export function targetOf(activity: Activity): string {
  const meta = activity.metadata;
  const targetId = text(activity.targetId);
  const metaPlace = text(meta?.placeId) || text(meta?.globalPlaceId);
  const actor = actorPathOf(activity);
  const place = (id: string | null) => (id ? placePath(id) : actor);
  switch (activity.type) {
    // targetId is the save
    case 'place_added': case 'place_liked': case 'place_discovered': case 'place_commented':
      return place(targetId || metaPlace);
    // targetId is the venue
    case 'photo_uploaded': return place(text(meta?.globalPlaceId) || targetId);
    case 'venue_announcement': case 'venue_offer': return place(targetId || metaPlace);
    // targetId is a comment, a photo, a check-in or a moment: the place lives in metadata
    case 'comment_liked': case 'check_in': case 'video_uploaded': case 'video_liked':
    case 'workout_shared': case 'run_shared':
      return place(metaPlace);
    case 'global_place_liked': return place(text(meta?.globalPlaceId) || text(meta?.placeId));
    case 'circle_created': case 'circle_liked': case 'circle_commented':
      return targetId ? circlePath(targetId) : actor;
    case 'comment_added':
      if (activity.targetType === 'circle' && targetId) return circlePath(targetId);
      if (activity.targetType === 'place' && targetId) return placePath(targetId);
      return place(metaPlace);
    case 'suggestion_sent': case 'suggestion_accepted': case 'profile_updated': case 'user_activity':
    case 'reaction_added': case 'postcard_sent': case 'postcard_mailed': case 'fridgemail_sent':
      return actor;
    default:
      // A type this build doesn't know: whatever it clearly points at, else the person
      if (activity.targetType === 'circle' && targetId) return circlePath(targetId);
      if (activity.targetType === 'place' && targetId) return placePath(targetId);
      if (activity.targetType === 'user' && targetId) return userPath(targetId);
      return place(metaPlace);
  }
}

export function activityCard(activity: Activity): ActivityCardCopy {
  return {
    actorName: text(activity.actor?.displayName) || 'Someone',
    actorPath: actorPathOf(activity),
    sentence: sentenceOf(activity),
    quote: quoteOf(activity),
    chip: chipOf(activity),
    pictures: picturesOf(activity),
    poster: posterOf(activity),
    target: targetOf(activity)
  };
}

const sameKind = (a: string, b: string): boolean => {
  const pairs = [['place_liked', 'global_place_liked'], ['place_commented', 'comment_added']];
  return a === b || pairs.some((pair) => pair.includes(a) && pair.includes(b));
};

function countedPhrase(type: string, count: number): string {
  switch (type) {
    case 'place_added': return `saved ${count} places`;
    case 'place_liked': case 'global_place_liked': return `liked ${count} places`;
    case 'place_commented': case 'comment_added': return `commented on ${count} places`;
    case 'comment_liked': return `liked ${count} comments`;
    case 'photo_uploaded': return `uploaded ${count} photos`;
    case 'video_uploaded': return `shared ${count} moments`;
    case 'video_liked': return `liked ${count} moments`;
    case 'circle_created': return `created ${count} circles`;
    case 'circle_liked': return `liked ${count} circles`;
    case 'circle_commented': return `commented on ${count} circles`;
    case 'suggestion_sent': return `sent ${count} suggestions`;
    case 'suggestion_accepted': return `accepted ${count} suggestions`;
    case 'reaction_added': return `reacted to ${count} posts`;
    default: return `shared ${count} updates`;
  }
}

/** One line for a burst by one person: "saved 5 places, uploaded 2 photos, and created a new circle Tucson". */
export function groupSummary(activities: Activity[]): string {
  const parts: string[] = [];
  const counted: string[] = [];
  activities.forEach((activity) => {
    if (counted.some((type) => sameKind(type, activity.type))) return;
    counted.push(activity.type);
    const count = activities.filter((other) => sameKind(other.type, activity.type)).length;
    parts.push(count === 1 ? sentenceOf(activity) : countedPhrase(activity.type, count));
  });
  if (parts.length === 0) return 'shared an update';
  if (parts.length === 1) return parts[0];
  if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
  return `${parts.slice(0, -1).join(', ')}, and ${parts[parts.length - 1]}`;
}
