import { describe, expect, it } from 'vitest';
import { categoryOf, plural, privacyName, timeAgo } from './labels';

describe('labels', () => {
  it('names every privacy tier, and a place that follows its circle', () => {
    expect(privacyName('innerCircle')).toBe('Inner Circle');
    expect(privacyName('myNetwork')).toBe('My Network');
    expect(privacyName('followCircle')).toBe('Same as its circle');
    expect(privacyName(undefined)).toBe('Same as its circle');
  });
  it('falls back to Other for a category it does not know', () => {
    expect(categoryOf('cafe').name).toBe('Café');
    expect(categoryOf('spaceport').id).toBe('other');
    expect(categoryOf(null).id).toBe('other');
  });
  it('counts and tells time', () => {
    expect(plural(1, 'place')).toBe('1 place');
    expect(plural(0, 'place')).toBe('0 places');
    const now = Date.parse('2026-11-26T12:00:00Z');
    expect(timeAgo('2026-11-26T11:59:40Z', now)).toBe('Just now');
    expect(timeAgo('2026-11-26T11:15:00Z', now)).toBe('45 min ago');
    expect(timeAgo('2026-11-26T07:00:00Z', now)).toBe('5 h ago');
    expect(timeAgo('nope', now)).toBe('');
  });
});
