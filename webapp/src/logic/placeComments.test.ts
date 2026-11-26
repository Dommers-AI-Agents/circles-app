import { describe, expect, it } from 'vitest';
import { authorName, canDeleteComment, canReplyTo, likedBy, ownsSocial, routeAfterMove, routeAfterUnsave, toggledLikes } from './placeComments';

describe('who may delete a comment', () => {
  const comment = { userId: 'author', placeId: 'saveX' };
  it('its author, wherever they see it', () => {
    expect(canDeleteComment(comment, 'author', 'saveY', false)).toBe(true);
  });
  it('the owner of the save it was written on', () => {
    expect(canDeleteComment(comment, 'me', 'saveX', true)).toBe(true);
  });
  it('not someone who merely saved the same venue', () => {
    expect(canDeleteComment(comment, 'me', 'saveY', true)).toBe(false);
  });
  it('not a viewer of someone else’s save', () => {
    expect(canDeleteComment(comment, 'me', 'saveX', false)).toBe(false);
  });
  it('nobody signed out', () => {
    expect(canDeleteComment(comment, undefined, 'saveX', true)).toBe(false);
  });
});

describe('comments and likes', () => {
  it('replies are one level deep', () => {
    expect(canReplyTo({ userId: 'a' })).toBe(true);
    expect(canReplyTo({ userId: 'a', parentCommentId: 'c1' })).toBe(false);
  });
  it('names the author, or "Someone"', () => {
    expect(authorName({ userId: 'a', user: { displayName: ' Ana ' } })).toBe('Ana');
    expect(authorName({ userId: 'a', user: null })).toBe('Someone');
  });
  it('knows whether I liked it', () => {
    expect(likedBy(['me', 'x'], 'me')).toBe(true);
    expect(likedBy(['x'], 'me')).toBe(false);
    expect(likedBy(undefined, 'me')).toBe(false);
    expect(likedBy(['me'], undefined)).toBe(false);
  });
  it('toggles my like in and out', () => {
    expect(toggledLikes(['x'], 'me')).toEqual(['x', 'me']);
    expect(toggledLikes(['x', 'me'], 'me')).toEqual(['x']);
    expect(toggledLikes(null, 'me')).toEqual(['me']);
  });
  it('knows when the social save is mine', () => {
    const mine = { id: 's1', circleId: 'c', privateNotes: '', userRating: null, privacy: 'followCircle' as const, tags: [] };
    expect(ownsSocial({ mine, socialId: 's1' })).toBe(true);
    expect(ownsSocial({ mine, socialId: 's2' })).toBe(false);
    expect(ownsSocial({ mine: null, socialId: 's1' })).toBe(false);
  });
});

describe('where the page goes after a write', () => {
  const venue = (globalPlaceId: string | null) => ({ globalPlaceId } as never);
  it('unsaving my own save opens the venue instead', () => {
    expect(routeAfterUnsave({ kind: 'mine', venue: venue('v1') })).toBe('/place/v1');
  });
  it('unsaving an unlinked save goes back', () => {
    expect(routeAfterUnsave({ kind: 'mine', venue: venue(null) })).toBe('');
  });
  it('stays when the link was someone else’s save or the venue', () => {
    expect(routeAfterUnsave({ kind: 'theirs', venue: venue('v1') })).toBeNull();
    expect(routeAfterUnsave({ kind: 'venue', venue: venue('v1') })).toBeNull();
  });
  it('a merged move follows the surviving save', () => {
    expect(routeAfterMove({ kind: 'mine' }, true, 's2')).toBe('/place/s2');
    expect(routeAfterMove({ kind: 'mine' }, false, 's1')).toBeNull();
    expect(routeAfterMove({ kind: 'venue' }, true, 's2')).toBeNull();
  });
});
