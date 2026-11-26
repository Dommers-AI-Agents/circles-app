// How the feed's rows are put together: pages joined without repeats, and a
// burst of one person's activities collapsed into one card. A port of
// HomeActivityFeedViewController.group and Logic/ActivityGroupLayout.swift.
import type { Activity } from '../api/feed';

export type FeedItem =
  | { kind: 'single'; activity: Activity }
  | { kind: 'group'; key: string; activities: Activity[] };

/** The longest gap between two neighbours of one burst */
export const GROUP_WINDOW_MS = 60 * 60 * 1000;
/** The most activities worth swiping through one at a time; a bigger burst gets "Show all N" */
export const MAX_GROUP_PAGES = 5;

/** Check-ins always stand alone; everything else can join a burst. */
export const isStandalone = (activity: Activity): boolean => activity.type === 'check_in';

const timeOf = (activity: Activity): number => {
  const time = activity.timestamp ? Date.parse(activity.timestamp) : NaN;
  return Number.isNaN(time) ? 0 : time;
};

/**
 * Collapses consecutive same-actor activities (rolling 60-minute window,
 * measured from the previous member) into groups of two or more. The feed is
 * newest first. A check-in in the middle of a burst doesn't break it: the
 * group sits where its newest member was.
 */
export function groupFeed(activities: Activity[]): FeedItem[] {
  const items: FeedItem[] = [];
  let pending: Activity[] = [];
  let pendingStart = 0;

  const flush = () => {
    if (pending.length === 0) return;
    const at = Math.min(pendingStart, items.length);
    const item: FeedItem = pending.length >= 2
      ? { kind: 'group', key: pending[0]._id, activities: pending }
      : { kind: 'single', activity: pending[0] };
    items.splice(at, 0, item);
    pending = [];
  };

  activities.forEach((activity) => {
    if (isStandalone(activity)) {
      items.push({ kind: 'single', activity });
      return;
    }
    if (pending.length > 0) {
      const last = pending[pending.length - 1];
      const sameActor = activity.actorId === pending[0].actorId;
      const withinWindow = timeOf(last) - timeOf(activity) <= GROUP_WINDOW_MS;
      if (sameActor && withinWindow) {
        pending.push(activity);
        return;
      }
      flush();
    }
    pendingStart = items.length;
    pending.push(activity);
  });
  flush();
  return items;
}

/** A small burst is one card you swipe through; a big one opens into full cards. */
export const groupLayout = (count: number): 'pages' | 'expandable' => (count <= MAX_GROUP_PAGES ? 'pages' : 'expandable');

/** Pages in order, each activity once (the server's offset can overlap the page before). */
export function mergePages(pages: { activities: Activity[] }[]): Activity[] {
  const seen = new Set<string>();
  const merged: Activity[] = [];
  pages.forEach((page) => page.activities.forEach((activity) => {
    if (!activity || !activity._id || seen.has(activity._id)) return;
    seen.add(activity._id);
    merged.push(activity);
  }));
  return merged;
}

/**
 * The offset of the next page, or undefined at the end. The server counts
 * the offset in rows it has handed out, so the next one is how many came
 * back so far (as the iOS app asks). A page that brought nothing new ends
 * the feed, or the load-more would ask for it forever.
 */
export function nextOffset(pages: { activities: Activity[]; hasMore: boolean }[]): number | undefined {
  if (pages.length === 0) return 0;
  const last = pages[pages.length - 1];
  if (!last.hasMore || last.activities.length === 0) return undefined;
  const before = new Set(mergePages(pages.slice(0, -1)).map((activity) => activity._id));
  if (pages.length > 1 && !last.activities.some((activity) => !before.has(activity._id))) return undefined;
  return pages.reduce((sum, page) => sum + page.activities.length, 0);
}
