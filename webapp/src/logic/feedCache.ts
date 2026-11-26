// Changing one row of the loaded feed in place (a reaction, a comment count)
// so the card answers the tap at once, and putting it back if the server
// says no. Pure: the cached pages in, new cached pages out.
import type { Activity } from '../api/feed';

export interface PagedRows<P> {
  pages: P[];
  pageParams: unknown[];
}

type FeedPageLike = { activities: Activity[] };

/** The row with this id, wherever it was loaded, or null. */
export function findActivity<P extends FeedPageLike>(data: PagedRows<P> | undefined, id: string): Activity | null {
  if (!data) return null;
  for (const page of data.pages) {
    const found = page.activities.find((activity) => activity._id === id);
    if (found) return found;
  }
  return null;
}

/** Every copy of the row (pages can overlap) passed through `change`; the rest untouched. */
export function patchActivity<P extends FeedPageLike>(
  data: PagedRows<P> | undefined,
  id: string,
  change: (activity: Activity) => Activity
): PagedRows<P> | undefined {
  if (!data) return data;
  let touched = false;
  const pages = data.pages.map((page) => {
    if (!page.activities.some((activity) => activity._id === id)) return page;
    touched = true;
    return { ...page, activities: page.activities.map((activity) => (activity._id === id ? change(activity) : activity)) };
  });
  return touched ? { ...data, pages } : data;
}

/** The comment count after adding (+1) or deleting (-1) one; never below zero. */
export const bumpComments = (activity: Activity, by: number): Activity =>
  ({ ...activity, commentCount: Math.max(0, (activity.commentCount || 0) + by) });
