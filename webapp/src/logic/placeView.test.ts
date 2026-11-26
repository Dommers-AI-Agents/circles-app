import { describe, expect, it } from 'vitest';
import { directionsHref, photoUrls, priceText, ratingText, telHref, viewFromSave, viewFromVenue, websiteHref } from './placeView';
import type { GlobalPlace, SavedPlace } from '../api/places';

const ME = 'me';
const THEM = 'them';

const save = (extra: Partial<SavedPlace> = {}): SavedPlace => ({
  _id: 'save1', name: 'Amélie’s', address: '380 S College St', category: 'cafe', globalPlaceId: 'venue1',
  location: { type: 'Point', coordinates: [-80.84, 35.22] }, photos: ['https://img/1.jpg'],
  rating: 4.5, userRatingsTotal: 1203, priceLevel: 1, phone: '(704) 555-0100', website: 'https://amelies.example',
  openingHours: [{ day: 1, open: '07:00', close: '15:00' }], addedBy: ME, circleId: 'c1',
  privateNotes: 'Salted caramel brownie', userRating: 9, tags: ['dessert'], likes: [THEM], commentsCount: 2,
  isFollowing: true, followAlerts: false, ...extra
});

const venue = (extra: Partial<GlobalPlace> = {}): GlobalPlace => ({
  _id: 'venue1', name: 'Amélie’s', address: '380 S College St', category: 'cafe', googlePlaceId: 'g1',
  location: { type: 'Point', coordinates: [-80.84, 35.22] },
  photos: [{ url: 'https://img/1.jpg' }, { url: 'https://img/gone.jpg', removedAt: '2026-11-01' }, { url: 'https://img/2.jpg' }],
  coverPhotoUrl: 'https://img/2.jpg',
  googleData: { rating: 4.5, userRatingsTotal: 1203, priceLevel: 1, phone: '(704) 555-0100', website: 'amelies.example', openingHours: [{ day: 0, open: null, close: null, isClosed: true }] },
  likes: [ME, THEM], commentsCount: 3, followers: [ME], alertFollowerIds: [ME], followersCount: 1, ...extra
});

describe('opened by one of my saves', () => {
  const view = viewFromSave('save1', save(), null, ME);
  it('is mine, with my notes, rating, circle and privacy', () => {
    expect(view.kind).toBe('mine');
    expect(view.mine).toEqual({ id: 'save1', circleId: 'c1', privateNotes: 'Salted caramel brownie', userRating: 9, privacy: 'followCircle', tags: ['dessert'] });
    expect(view.savedBy).toBeNull();
  });
  it('carries the venue and the social state', () => {
    expect(view.venue.name).toBe('Amélie’s');
    expect(view.venue.rating).toBe(4.5);
    expect(view.venue.hours).toHaveLength(1);
    expect(view.likes).toEqual([THEM]);
    expect(view.isFollowing).toBe(true);
    expect(view.socialId).toBe('save1');
  });
  it('shares and follows by the venue id, falling back to the save for an unlinked one', () => {
    expect(view.shareId).toBe('venue1');
    expect(view.storeId).toBe('venue1');
    expect(viewFromSave('save1', save({ globalPlaceId: null }), null, ME).shareId).toBe('save1');
  });
  it('is waiting for review when the server says so', () => {
    expect(viewFromSave('save1', save({ approvalStatus: 'pending' }), null, ME).pending).toBe(true);
    expect(viewFromSave('save1', save({ privacyBeforeApproval: 'public' }), null, ME, 'pending').pending).toBe(true);
    expect(viewFromSave('save1', save({ privacyBeforeApproval: 'public' }), null, ME, 'rejected').pending).toBe(false);
    expect(view.pending).toBe(false);
  });
});

describe("opened by someone else's save", () => {
  const theirs = save({ _id: 'save2', addedBy: THEM, privateNotes: undefined, userRating: 3,
    addedByUser: { id: THEM, displayName: 'Blake Rivers', profilePicture: 'https://img/b.jpg' } });
  it('names whose it is and shows none of their personal fields as mine', () => {
    const view = viewFromSave('save2', theirs, null, ME);
    expect(view.kind).toBe('theirs');
    expect(view.savedBy).toEqual({ id: THEM, name: 'Blake Rivers', photo: 'https://img/b.jpg' });
    expect(view.mine).toBeNull();
  });
  it('uses my own save of the venue for my notes, and their save for likes and comments', () => {
    const view = viewFromSave('save2', theirs, save(), ME);
    expect(view.mine?.id).toBe('save1');
    expect(view.mine?.privateNotes).toBe('Salted caramel brownie');
    expect(view.socialId).toBe('save2');
  });
  it('reads the older {name, photo} shape too, and never crashes without one', () => {
    expect(viewFromSave('save2', { ...theirs, addedByUser: { name: 'Blake', photo: null } }, null, ME).savedBy)
      .toEqual({ id: THEM, name: 'Blake', photo: null });
    expect(viewFromSave('save2', { ...theirs, addedByUser: null }, null, ME).savedBy).toEqual({ id: THEM, name: 'Someone', photo: null });
  });
});

describe('opened by a venue id', () => {
  it('reads rating, hours and contact details from under googleData', () => {
    const view = viewFromVenue('venue1', venue(), null, ME);
    expect(view.kind).toBe('venue');
    expect(view.venue.rating).toBe(4.5);
    expect(view.venue.priceLevel).toBe(1);
    expect(view.venue.phone).toBe('(704) 555-0100');
    expect(view.venue.hours).toEqual([{ day: 0, open: null, close: null, isClosed: true }]);
  });
  it('puts the cover first and leaves out removed photos', () => {
    expect(viewFromVenue('venue1', venue(), null, ME).venue.photos).toEqual(['https://img/2.jpg', 'https://img/1.jpg']);
  });
  it('works out follow, bell and likes from the raw lists', () => {
    const view = viewFromVenue('venue1', venue(), null, ME);
    expect(view.isFollowing).toBe(true);
    expect(view.followAlerts).toBe(true);
    expect(view.likes).toContain(ME);
    const stranger = viewFromVenue('venue1', venue(), null, 'nobody');
    expect(stranger.isFollowing).toBe(false);
    expect(stranger.followAlerts).toBe(false);
  });
  it('has no bell for someone who stopped following', () => {
    expect(viewFromVenue('venue1', venue({ followers: [] }), null, ME).followAlerts).toBe(false);
  });
  it('with nobody\'s save to go through, likes and comments are read-only', () => {
    const view = viewFromVenue('venue1', venue(), null, ME);
    expect(view.socialId).toBeNull();
    expect(view.mine).toBeNull();
    expect(view.savedBy).toBeNull();
  });
  it('finds my own save when the server hands it back', () => {
    const view = viewFromVenue('venue1', venue(), save(), ME);
    expect(view.mine?.id).toBe('save1');
    expect(view.socialId).toBe('save1');
    expect(view.savedBy).toBeNull();
  });
  it("never shows another person's notes as mine", () => {
    const leaked = save({ _id: 'save2', addedBy: THEM, privateNotes: 'their secret', addedByUser: { id: THEM, displayName: 'Blake' } });
    const view = viewFromVenue('venue1', venue(), leaked, ME);
    expect(view.mine).toBeNull();
    expect(view.savedBy?.name).toBe('Blake');
    expect(view.socialId).toBe('save2');
    expect(JSON.stringify(view)).not.toContain('their secret');
  });
  it('survives a bare venue record', () => {
    const view = viewFromVenue('v', { _id: 'v' }, null, undefined);
    expect(view.venue).toMatchObject({ name: 'A place', address: '', photos: [], rating: null, hours: [], category: 'other' });
    expect(view.pending).toBe(false);
    expect(viewFromVenue('v', { _id: 'v', approvalStatus: 'pending' }, null, ME).pending).toBe(true);
  });
});

describe('small pieces', () => {
  it('keeps only https photos, once each', () => {
    expect(photoUrls(['https://a/1.jpg', { url: 'https://a/1.jpg' }, 'http://a/2.jpg', null, { url: null }, 7])).toEqual(['https://a/1.jpg']);
    expect(photoUrls(undefined)).toEqual([]);
  });
  it('writes price and rating', () => {
    expect(priceText(2)).toBe('$$');
    expect(priceText(0)).toBe('');
    expect(priceText(null)).toBe('');
    expect(ratingText(4.5, 1203)).toBe('4.5 (1,203)');
    expect(ratingText(4, null)).toBe('4.0');
    expect(ratingText(null, 10)).toBe('');
  });
  it('links only to web addresses', () => {
    expect(websiteHref('amelies.example')).toBe('https://amelies.example/');
    expect(websiteHref('http://amelies.example/menu')).toBe('http://amelies.example/menu');
    expect(websiteHref('javascript:alert(1)')).toBeNull();
    expect(websiteHref('')).toBeNull();
  });
  it('dials only real numbers', () => {
    expect(telHref('(704) 555-0100')).toBe('tel:7045550100');
    expect(telHref('+1 704-555-0100')).toBe('tel:+17045550100');
    expect(telHref('n/a')).toBeNull();
  });
  it('gives directions latitude first', () => {
    expect(directionsHref(35.22, -80.84)).toBe('https://www.google.com/maps/dir/?api=1&destination=35.22,-80.84');
  });
});
