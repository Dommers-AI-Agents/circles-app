import { describe, expect, it } from 'vitest';
import type { Activity } from '../api/feed';
import { bumpComments, findActivity, patchActivity } from './feedCache';

const row = (id: string, extra: Partial<Activity> = {}): Activity => ({ _id: id, type: 'place_added', actorId: 'u1', ...extra });
const data = () => ({
  pages: [
    { activities: [row('a'), row('b')], hasMore: true, offset: 0 },
    { activities: [row('b'), row('c')], hasMore: false, offset: 2 }
  ],
  pageParams: [0, 2]
});

describe('findActivity', () => {
  it('finds a row on any page', () => {
    expect(findActivity(data(), 'c')?._id).toBe('c');
  });
  it('is null when absent or nothing is loaded', () => {
    expect(findActivity(data(), 'zz')).toBeNull();
    expect(findActivity(undefined, 'a')).toBeNull();
  });
});

describe('patchActivity', () => {
  it('changes every copy of the row and leaves the others alone', () => {
    const before = data();
    const after = patchActivity(before, 'b', (a) => ({ ...a, commentCount: 3 }))!;
    expect(after.pages[0].activities[1].commentCount).toBe(3);
    expect(after.pages[1].activities[0].commentCount).toBe(3);
    expect(after.pages[0].activities[0]).toBe(before.pages[0].activities[0]);
    expect(after.pageParams).toEqual([0, 2]);
  });
  it('does not mutate the cache it was given', () => {
    const before = data();
    patchActivity(before, 'a', (a) => ({ ...a, commentCount: 9 }));
    expect(before.pages[0].activities[0].commentCount).toBeUndefined();
  });
  it('returns the same object when the row is not loaded', () => {
    const before = data();
    expect(patchActivity(before, 'zz', (a) => a)).toBe(before);
    expect(patchActivity(undefined, 'a', (a) => a)).toBeUndefined();
  });
  it('a page without the row keeps its identity', () => {
    const before = data();
    const after = patchActivity(before, 'a', (a) => ({ ...a, reactionCount: 1 }))!;
    expect(after.pages[1]).toBe(before.pages[1]);
  });
});

describe('bumpComments', () => {
  it('adds and takes away', () => {
    expect(bumpComments(row('a', { commentCount: 2 }), 1).commentCount).toBe(3);
    expect(bumpComments(row('a', { commentCount: 2 }), -1).commentCount).toBe(1);
  });
  it('starts from zero and never goes below it', () => {
    expect(bumpComments(row('a'), 1).commentCount).toBe(1);
    expect(bumpComments(row('a'), -1).commentCount).toBe(0);
  });
});
