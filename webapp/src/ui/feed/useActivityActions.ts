// Reacting to a row: the card changes at once, the server is told, and the
// row goes back the way it was if the server says no.
import { useQueryClient } from '@tanstack/react-query';
import { react, unreact, type Activity, type FeedPage } from '../../api/feed';
import { messageOf } from '../../api/client';
import { findActivity, patchActivity, type PagedRows } from '../../logic/feedCache';
import { applyReaction } from '../../logic/reactions';
import { toast } from '../kit';

export const FEED_KEY = ['feed'] as const;
type FeedData = PagedRows<FeedPage>;

export function useReact() {
  const queryClient = useQueryClient();
  return async (activity: Activity, emoji: string) => {
    const before = findActivity(queryClient.getQueryData<FeedData>(FEED_KEY), activity._id) || activity;
    const after = applyReaction(before, emoji);
    // A refetch landing now would draw the old numbers over the tap
    await queryClient.cancelQueries({ queryKey: FEED_KEY, exact: true });
    queryClient.setQueryData<FeedData>(FEED_KEY, (data) => patchActivity(data, activity._id, () => after));
    try {
      if (after.userReaction) await react(activity._id, after.userReaction);
      else await unreact(activity._id);
    } catch (error) {
      queryClient.setQueryData<FeedData>(FEED_KEY, (data) => patchActivity(data, activity._id, (row) => ({
        ...row,
        userReaction: before.userReaction,
        reactionCount: before.reactionCount,
        reactionSummary: before.reactionSummary
      })));
      toast(`Your reaction didn't save. ${messageOf(error)}`);
    }
  };
}
