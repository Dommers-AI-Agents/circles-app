import { describe, expect, it } from 'vitest';
import { mapLink, outgoingShare, shareCard } from './messageShare';

describe('outgoingShare', () => {
  it('a place carries its name, and only what is known', () => {
    expect(outgoingShare({ kind: 'place', placeId: 'p1', placeName: 'Pasta & Provisions', address: '1600 S Mint St', photoUrl: 'https://x/p.jpg', lat: 35.2, lng: -80.8 }))
      .toEqual({ type: 'place_share', content: '📍 Pasta & Provisions', metadata: { placeName: 'Pasta & Provisions', placeId: 'p1', address: '1600 S Mint St', photoUrl: 'https://x/p.jpg', lat: 35.2, lng: -80.8 } });
    expect(outgoingShare({ kind: 'place', placeName: 'Somewhere', address: '', photoUrl: null, lat: 35.2 }))
      .toEqual({ type: 'place_share', content: '📍 Somewhere', metadata: { placeName: 'Somewhere' } });
  });
  it('refuses coordinates that are not on the globe', () => {
    expect(outgoingShare({ kind: 'place', placeName: 'X', lat: 91, lng: 0 }).metadata).toEqual({ placeName: 'X' });
    expect(outgoingShare({ kind: 'place', placeName: 'X', lat: 0, lng: 0 }).metadata).toEqual({ placeName: 'X', lat: 0, lng: 0 });
  });
  it('a circle carries its id and name, the count and cover when known', () => {
    expect(outgoingShare({ kind: 'circle', circleId: 'c1', circleName: 'Date night', placeCount: 0, coverUrl: 'https://x/c.jpg' }))
      .toEqual({ type: 'circle_share', content: '⭕️ Date night', metadata: { circleId: 'c1', circleName: 'Date night', placeCount: 0, coverUrl: 'https://x/c.jpg' } });
    expect(outgoingShare({ kind: 'circle', circleId: 'c1', circleName: 'Coffee' }).metadata).toEqual({ circleId: 'c1', circleName: 'Coffee' });
  });
});

describe('shareCard', () => {
  it('reads back what was sent', () => {
    const place = outgoingShare({ kind: 'place', placeId: 'p 1', placeName: 'Pasta', address: 'Mint St', photoUrl: 'https://x/p.jpg', lat: 35.2, lng: -80.8 });
    expect(shareCard(place.type, place.metadata)).toEqual({
      kind: 'place', title: 'Pasta', subtitle: 'Mint St', imageUrl: 'https://x/p.jpg', symbol: '📍', path: '/place/p%201', mapUrl: mapLink(35.2, -80.8)
    });
    const circle = outgoingShare({ kind: 'circle', circleId: 'c1', circleName: 'Coffee', placeCount: 1 });
    expect(shareCard(circle.type, circle.metadata)).toEqual({ kind: 'circle', title: 'Coffee', subtitle: '1 place', imageUrl: undefined, symbol: '⭕️', path: '/circle/c1' });
  });
  it('a place nobody saved opens a map instead of a page', () => {
    const card = shareCard('place_share', { placeName: 'Apple result', lat: '35.2', lng: '-80.8' });
    expect(card?.path).toBeUndefined();
    expect(card?.mapUrl).toBe('https://www.google.com/maps/search/?api=1&query=35.2%2C-80.8');
  });
  it('counts places in words', () => {
    expect(shareCard('circle_share', { circleId: 'c', circleName: 'N', placeCount: 12 })?.subtitle).toBe('12 places');
    expect(shareCard('circle_share', { circleId: 'c', circleName: 'N', placeCount: '3' })?.subtitle).toBe('3 places');
    expect(shareCard('circle_share', { circleId: 'c', circleName: 'N' })?.subtitle).toBeUndefined();
  });
  it('a location needs a real coordinate', () => {
    expect(shareCard('location', { lat: 35.2, lng: -80.8, address: 'Here' })).toEqual({ kind: 'location', title: 'My location', subtitle: 'Here', symbol: '📌', mapUrl: mapLink(35.2, -80.8) });
    expect(shareCard('location', { lat: 135.2, lng: -80.8 })).toBeNull();
    expect(shareCard('location', {})).toBeNull();
  });
  it('is nothing for other messages or missing names', () => {
    expect(shareCard('text', { placeName: 'X' })).toBeNull();
    expect(shareCard('place_share', {})).toBeNull();
    expect(shareCard('place_share', null)).toBeNull();
    expect(shareCard('circle_share', { circleName: 'No id' })).toBeNull();
  });
});
