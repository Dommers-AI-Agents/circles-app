import { describe, expect, it } from 'vitest';
import type { Activity } from '../api/feed';
import { groupFeed, groupLayout, mergePages, nextOffset } from './activityGroups';

const at = (minutesAgo: number) => new Date(Date.UTC(2026, 10, 25, 12, 0, 0) - minutesAgo * 60_000).toISOString();
const row = (id: string, actorId: string, minutesAgo: number, type = 'place_added'): Activity =>
  ({ _id: id, type, actorId, timestamp: at(minutesAgo) });
const shape = (items: ReturnType<typeof groupFeed>) =>
  items.map((item) => (item.kind === 'single' ? item.activity._id : `[${item.activities.map((a) => a._id).join(',')}]`));

describe('groupFeed', () => {
  it('collapses one person\'s consecutive rows within an hour of each other', () => {
    expect(shape(groupFeed([row('a', 'u1', 0), row('b', 'u1', 30), row('c', 'u1', 80), row('d', 'u2', 90)])))
      .toEqual(['[a,b,c]', 'd']);
  });
  it('measures the hour from the previous row, not the first (a rolling window)', () => {
    expect(shape(groupFeed([row('a', 'u1', 0), row('b', 'u1', 61)]))).toEqual(['a', 'b']);
    expect(shape(groupFeed([row('a', 'u1', 0), row('b', 'u1', 60)]))).toEqual(['[a,b]']);
  });
  it('another person ends the burst', () => {
    expect(shape(groupFeed([row('a', 'u1', 0), row('b', 'u2', 1), row('c', 'u1', 2)]))).toEqual(['a', 'b', 'c']);
  });
  it('keeps check-ins alone without breaking the burst around them', () => {
    const items = groupFeed([row('a', 'u1', 0), row('k', 'u1', 5, 'check_in'), row('b', 'u1', 10), row('k2', 'u2', 12, 'check_in')]);
    expect(shape(items)).toEqual(['[a,b]', 'k', 'k2']);
    expect(items[0]).toMatchObject({ kind: 'group', key: 'a' });
  });
  it('leaves a lone row as itself and survives missing times', () => {
    expect(shape(groupFeed([row('a', 'u1', 0)]))).toEqual(['a']);
    expect(shape(groupFeed([]))).toEqual([]);
    expect(shape(groupFeed([{ _id: 'x', type: 'zzz', actorId: 'u1' }, { _id: 'y', type: 'zzz', actorId: 'u1' }]))).toEqual(['[x,y]']);
  });
  it('swipes a small burst and opens a big one', () => {
    expect(groupLayout(2)).toBe('pages');
    expect(groupLayout(5)).toBe('pages');
    expect(groupLayout(6)).toBe('expandable');
  });
});

describe('paging', () => {
  const page = (ids: string[], hasMore: boolean) => ({ activities: ids.map((id) => row(id, 'u1', 0)), hasMore });
  it('joins pages without repeats, in order', () => {
    expect(mergePages([page(['a', 'b'], true), page(['b', 'c'], false)]).map((a) => a._id)).toEqual(['a', 'b', 'c']);
  });
  it('asks next for as many rows as came back so far', () => {
    expect(nextOffset([page(['a', 'b'], true)])).toBe(2);
    expect(nextOffset([page(['a', 'b'], true), page(['b', 'c'], true)])).toBe(4);
  });
  it('stops at the end, on an empty page, and on a page with nothing new', () => {
    expect(nextOffset([page(['a'], false)])).toBeUndefined();
    expect(nextOffset([page(['a'], true), page([], true)])).toBeUndefined();
    expect(nextOffset([page(['a', 'b'], true), page(['a', 'b'], true)])).toBeUndefined();
  });
});
