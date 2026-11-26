import { describe, expect, it } from 'vitest';
import { profileChanges, profileProblem } from './profileChanges';

const saved = { displayName: 'Alex Rivers', bio: 'Tacos and trails', zipcode: '28203', profilePicture: 'https://x/a.jpg' };
const form = { displayName: 'Alex Rivers', bio: 'Tacos and trails', zipcode: '28203' };

describe('profileChanges', () => {
  it('sends nothing when nothing changed', () => {
    expect(profileChanges(saved, form)).toEqual({});
    expect(profileChanges(saved, { ...form, displayName: '  Alex   Rivers ' })).toEqual({});
  });
  it('sends only the field that changed', () => {
    expect(profileChanges(saved, { ...form, bio: 'Tacos' })).toEqual({ bio: 'Tacos' });
    expect(profileChanges(saved, { ...form, zipcode: '85128' })).toEqual({ zipcode: '85128' });
    expect(profileChanges(saved, { ...form, displayName: 'Alex R' })).toEqual({ displayName: 'Alex R' });
  });
  it('can clear a bio or a zip code', () => {
    expect(profileChanges(saved, { ...form, bio: '', zipcode: '' })).toEqual({ bio: '', zipcode: '' });
  });
  it('treats missing saved values as empty', () => {
    expect(profileChanges({ displayName: 'Alex Rivers', bio: null, zipcode: null }, { displayName: 'Alex Rivers', bio: '', zipcode: '' })).toEqual({});
  });
  it('sends a new picture, never an unchanged or empty one', () => {
    expect(profileChanges(saved, { ...form, profilePicture: 'https://x/b.jpg' })).toEqual({ profilePicture: 'https://x/b.jpg' });
    expect(profileChanges(saved, { ...form, profilePicture: 'https://x/a.jpg' })).toEqual({});
    expect(profileChanges(saved, { ...form, profilePicture: '' })).toEqual({});
  });
});

describe('profileProblem', () => {
  it('passes a good form', () => {
    expect(profileProblem(form)).toBe('');
    expect(profileProblem({ ...form, zipcode: '' })).toBe('');
  });
  it('wants a real name', () => {
    expect(profileProblem({ ...form, displayName: ' A ' })).toMatch(/at least 2/);
    expect(profileProblem({ ...form, displayName: 'x'.repeat(51) })).toMatch(/up to 50/);
  });
  it('wants a 5-digit zip code', () => {
    expect(profileProblem({ ...form, zipcode: '2820' })).toMatch(/5 digits/);
    expect(profileProblem({ ...form, zipcode: 'abcde' })).toMatch(/5 digits/);
  });
  it('caps the bio', () => {
    expect(profileProblem({ ...form, bio: 'x'.repeat(301) })).toMatch(/up to 300/);
  });
});
