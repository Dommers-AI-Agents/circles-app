import { describe, expect, it } from 'vitest';
import { REACTIONS, applyReaction, topReactions } from './reactions';

describe('REACTIONS', () => {
  it('is the seven the server accepts (backend/models/FirestoreModels.js), byte for byte', () => {
    expect(REACTIONS.map((r) => r.emoji)).toEqual(['\u{1F44D}', '❤️', '\u{1F389}', '\u{1F4AA}', '\u{1F4A1}', '\u{1F606}', '\u{1F60B}']);
  });
});

describe('applyReaction', () => {
  it('adds my first reaction', () => {
    expect(applyReaction({ userReaction: null, reactionCount: 0, reactionSummary: [] }, '👍'))
      .toEqual({ userReaction: '👍', reactionCount: 1, reactionSummary: [{ emoji: '👍', count: 1 }] });
  });
  it('adds to what others gave and keeps the most used first', () => {
    const next = applyReaction({ userReaction: null, reactionCount: 3, reactionSummary: [{ emoji: '🎉', count: 2 }, { emoji: '👍', count: 1 }] }, '👍');
    expect(next).toEqual({ userReaction: '👍', reactionCount: 4, reactionSummary: [{ emoji: '🎉', count: 2 }, { emoji: '👍', count: 2 }] });
  });
  it('takes mine off when I tap it again', () => {
    expect(applyReaction({ userReaction: '👍', reactionCount: 1, reactionSummary: [{ emoji: '👍', count: 1 }] }, '👍'))
      .toEqual({ userReaction: null, reactionCount: 0, reactionSummary: [] });
  });
  it('swaps without changing the total', () => {
    const next = applyReaction({ userReaction: '👍', reactionCount: 3, reactionSummary: [{ emoji: '👍', count: 2 }, { emoji: '🎉', count: 1 }] }, '🎉');
    expect(next).toEqual({ userReaction: '🎉', reactionCount: 3, reactionSummary: [{ emoji: '🎉', count: 2 }, { emoji: '👍', count: 1 }] });
  });
  it('is its own undo', () => {
    const before = { userReaction: null, reactionCount: 2, reactionSummary: [{ emoji: '🎉', count: 2 }] };
    expect(applyReaction(applyReaction(before, '💡'), '💡')).toEqual(before);
  });
  it('copes with rows that carry no numbers, and never counts below zero', () => {
    expect(applyReaction({}, '😋')).toEqual({ userReaction: '😋', reactionCount: 1, reactionSummary: [{ emoji: '😋', count: 1 }] });
    expect(applyReaction({ userReaction: '👍', reactionCount: 0, reactionSummary: null }, '👍'))
      .toEqual({ userReaction: null, reactionCount: 0, reactionSummary: [] });
  });
  it('keeps the row\'s other fields', () => {
    const row: { _id: string; commentCount: number; userReaction?: string | null } = { _id: 'a', commentCount: 4 };
    expect(applyReaction(row, '👍')).toMatchObject({ _id: 'a', commentCount: 4 });
  });
});

describe('topReactions', () => {
  it('is the three most used', () => {
    expect(topReactions([{ emoji: 'a', count: 1 }, { emoji: 'b', count: 5 }, { emoji: 'c', count: 0 }, { emoji: 'd', count: 2 }, { emoji: 'e', count: 3 }]))
      .toEqual([{ emoji: 'b', count: 5 }, { emoji: 'e', count: 3 }, { emoji: 'd', count: 2 }]);
    expect(topReactions(null)).toEqual([]);
  });
});
