// Reactions on an Activity row: the app's seven emoji, and how a row's
// numbers change the moment I react (before the server answers).
// Mirrors iOS Models/ReactionStyle and Activity.withReaction.
import type { ReactionSummary } from '../api/feed';

export const REACTIONS: { emoji: string; name: string }[] = [
  { emoji: '👍', name: 'Like' },
  { emoji: '❤️', name: 'Love' },
  { emoji: '🎉', name: 'Celebrate' },
  { emoji: '💪', name: 'Support' },
  { emoji: '💡', name: 'Insightful' },
  { emoji: '😆', name: 'Funny' },
  { emoji: '😋', name: 'Yum' }
];

export interface ReactionState {
  userReaction?: string | null;
  reactionCount?: number;
  reactionSummary?: ReactionSummary[] | null;
}

/**
 * The row after I tap `emoji`: tapping the one I already gave takes it off,
 * another one swaps it, none yet adds it. Counts never go below zero and
 * the summary stays sorted, most used first.
 */
export function applyReaction<T extends ReactionState>(row: T, emoji: string): T {
  const current = row.userReaction || null;
  const next = current === emoji ? null : emoji;
  const counts = new Map<string, number>();
  (row.reactionSummary || []).forEach((entry) => {
    if (entry && entry.emoji && entry.count > 0) counts.set(entry.emoji, entry.count);
  });
  if (current) {
    const left = (counts.get(current) || 0) - 1;
    if (left > 0) counts.set(current, left); else counts.delete(current);
  }
  if (next) counts.set(next, (counts.get(next) || 0) + 1);
  const total = Math.max(0, (row.reactionCount || 0) + (next ? 1 : 0) - (current ? 1 : 0));
  // A stable sort: emoji with the same count keep the order they had
  const reactionSummary = Array.from(counts, ([e, count]) => ({ emoji: e, count })).sort((a, b) => b.count - a.count);
  return { ...row, userReaction: next, reactionCount: Math.max(total, next ? 1 : 0), reactionSummary };
}

/** The chips under a card: the three most used, with counts. */
export const topReactions = (summary: ReactionSummary[] | null | undefined, max = 3): ReactionSummary[] =>
  (summary || []).filter((entry) => entry && entry.emoji && entry.count > 0).slice().sort((a, b) => b.count - a.count).slice(0, max);
