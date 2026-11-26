import { describe, expect, it } from 'vitest';
import { formOf, ratingWord, saveChanges, saveTargets, startingCircle, tagsOf } from './placeSave';
import type { MySave } from './placeView';
import type { Circle } from '../api/types';

const save: MySave = { id: 's1', circleId: 'c1', privateNotes: 'Ask for the patio', userRating: 8, privacy: 'innerCircle', tags: ['patio'] };

describe('editing my save', () => {
  it('sends nothing when nothing changed, so the privacy is never written back', () => {
    expect(saveChanges(save, formOf(save))).toEqual({});
    expect(saveChanges(save, { ...formOf(save), privateNotes: ' Ask for the patio ' })).toEqual({});
  });
  it('sends only the notes when only the notes changed', () => {
    expect(saveChanges(save, { ...formOf(save), privateNotes: 'Closed Mondays' })).toEqual({ privateNotes: 'Closed Mondays' });
  });
  it('clears notes and a rating with empty values, not by leaving them out', () => {
    expect(saveChanges(save, { ...formOf(save), privateNotes: '', userRating: null })).toEqual({ privateNotes: '', userRating: null });
  });
  it('keeps a rating inside 0–10 and whole', () => {
    expect(saveChanges(save, { ...formOf(save), userRating: 11 })).toEqual({ userRating: 10 });
    expect(saveChanges(save, { ...formOf(save), userRating: 0 })).toEqual({ userRating: 0 });
    expect(saveChanges(save, { ...formOf(save), userRating: 8.2 })).toEqual({});
  });
  it('sends privacy only when it was changed, "Same as its circle" included', () => {
    expect(saveChanges(save, { ...formOf(save), privacy: 'followCircle' })).toEqual({ privacy: 'followCircle' });
    const following: MySave = { ...save, privacy: 'followCircle' };
    expect(saveChanges(following, formOf(following))).toEqual({});
    expect(saveChanges(following, { ...formOf(following), privacy: 'private' })).toEqual({ privacy: 'private' });
  });
  it('sends tags when they differ', () => {
    expect(saveChanges(save, { ...formOf(save), tags: ['patio', 'brunch'] })).toEqual({ tags: ['patio', 'brunch'] });
    expect(saveChanges(save, { ...formOf(save), tags: [] })).toEqual({ tags: [] });
  });
});

describe('tags', () => {
  it('splits on commas, trims, and drops blanks and repeats', () => {
    expect(tagsOf('date night,  Patio ,patio,, ')).toEqual(['date night', 'Patio']);
    expect(tagsOf('')).toEqual([]);
  });
});

const circle = (id: string, extra: Partial<Circle> = {}): Circle => ({ _id: id, name: id, owner: 'me', privacy: 'public', ...extra });

describe('which circle a save goes to', () => {
  const circles = [circle('zebra'), circle('checkins', { isCheckInCircle: true }), circle('follows', { isFollowedPlacesCircle: true }),
    circle('theirs', { owner: 'them' }), circle('apple')];
  it("offers my own circles in the server's order, without the ones the app fills itself", () => {
    expect(saveTargets(circles, 'me').map((c) => c._id)).toEqual(['zebra', 'apple']);
  });
  it('starts on the circle used last when it is still there', () => {
    expect(startingCircle(saveTargets(circles, 'me'), 'apple')).toBe('apple');
  });
  it('falls back to the first circle', () => {
    expect(startingCircle(saveTargets(circles, 'me'), 'gone')).toBe('zebra');
    expect(startingCircle(saveTargets(circles, 'me'), 'follows')).toBe('zebra');
    expect(startingCircle(saveTargets(circles, 'me'), null)).toBe('zebra');
    expect(startingCircle([], 'apple')).toBeNull();
  });
});

describe('rating words', () => {
  it('names each end of the scale', () => {
    expect(ratingWord(null)).toBe('Not rated');
    expect(ratingWord(10)).toBe('A favorite');
    expect(ratingWord(0)).toBe('Not for me');
  });
});
