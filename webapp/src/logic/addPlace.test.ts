import { describe, expect, it } from 'vitest';
import {
  buildSaveBody, coordinatesText, duplicateOf, handProblem, initialCircle, knownCategory, middleOf, outcomeOf,
  type PickedVenue, type SaveChoices
} from './addPlace';
import type { Circle } from '../api/types';

const at = { lat: 35.2242849, lng: -80.8452061 };
const catalog: PickedVenue = {
  name: "Amélie's Uptown | French Bakery & Cafe", address: '380 S College St, Charlotte, NC 28202, USA', at,
  category: 'cafe', source: 'catalog', globalPlaceId: 'uB86AgyHOtjBAAaGbmmY'
};
const osm: PickedVenue = { name: '  Amelie’s  ', address: '380 South College Street, Charlotte', at, category: 'cafe', source: 'osm' };
const choices: SaveChoices = { circleId: 'c1', category: 'cafe', privacy: 'followCircle', privateNotes: '', userRating: null };

describe('the save body', () => {
  it('sends a catalog pick with its venue id, name and address as they are', () => {
    expect(buildSaveBody(catalog, choices)).toEqual({
      name: catalog.name, address: catalog.address, location: { type: 'Point', coordinates: [at.lng, at.lat] },
      category: 'cafe', circleId: 'c1', privacy: 'followCircle', globalPlaceId: 'uB86AgyHOtjBAAaGbmmY'
    });
  });
  it('never sends a venue id, a Google id or a map-source claim for an OpenStreetMap or typed place', () => {
    const body = buildSaveBody(osm, choices) as unknown as Record<string, unknown>;
    expect(body.name).toBe('Amelie’s');
    expect(body).not.toHaveProperty('globalPlaceId');
    expect(body).not.toHaveProperty('googlePlaceId');
    expect(body).not.toHaveProperty('appleMatched');
    expect(body).not.toHaveProperty('force');
  });
  it('uses the coordinates when a typed place has no address', () => {
    expect(buildSaveBody({ ...osm, source: 'hand', address: '  ' }, choices).address).toBe(coordinatesText(at));
    expect(coordinatesText({ lat: 35.2, lng: -80.84 })).toBe('35.20000, -80.84000');
  });
  it('sends notes and a whole 0–10 rating only when given', () => {
    const body = buildSaveBody(osm, { ...choices, privateNotes: '  Ask for the window seat ', userRating: 8.4, privacy: 'innerCircle' });
    expect(body).toMatchObject({ privateNotes: 'Ask for the window seat', userRating: 8, privacy: 'innerCircle' });
    expect(buildSaveBody(osm, { ...choices, userRating: 14 }).userRating).toBe(10);
    expect(buildSaveBody(osm, { ...choices, userRating: 0 }).userRating).toBe(0);
    expect(buildSaveBody(osm, choices)).not.toHaveProperty('userRating');
    expect(buildSaveBody(osm, choices)).not.toHaveProperty('privateNotes');
  });
  it('adds force only for "Add anyway"', () => {
    expect(buildSaveBody(osm, choices, { force: true }).force).toBe(true);
  });
  it('turns a category the server does not know into "other"', () => {
    expect(knownCategory('bakery')).toBe('other');
    expect(knownCategory(undefined)).toBe('other');
    expect(buildSaveBody(osm, { ...choices, category: 'bakery' }).category).toBe('other');
  });
});

describe('a place typed by hand', () => {
  it('needs a name and a pin', () => {
    expect(handProblem(' ', at)).toBe('Give the place a name.');
    expect(handProblem('Grandma’s porch', null)).toBe('Tap the map to put a pin where the place is.');
    expect(handProblem('Grandma’s porch', at)).toBeNull();
  });
});

describe('the circle a save starts on', () => {
  const circle = (id: string) => ({ _id: id, name: id, owner: 'me', privacy: 'public' }) as Circle;
  const targets = [circle('a'), circle('b'), circle('c')];
  it('takes the one in the link first', () => {
    expect(initialCircle(targets, 'c', 'b')).toBe('c');
  });
  it('then the one used last, then the first in my order', () => {
    expect(initialCircle(targets, null, 'b')).toBe('b');
    expect(initialCircle(targets, 'gone', 'gone-too')).toBe('a');
    expect(initialCircle([], 'a', 'b')).toBeNull();
  });
});

describe('the duplicate answer', () => {
  it('names the circle the server named', () => {
    expect(duplicateOf({
      code: 'DUPLICATE_PLACE', existingPlaceId: 'p9', existingCircleId: 'c7', existingCircleName: 'Coffee',
      message: "You already have Amelie's in Coffee"
    }, 'Date night')).toEqual({ existingPlaceId: 'p9', title: 'Already in Coffee', message: "You already have Amelie's in Coffee" });
  });
  it("falls back to the circle I was saving to when the server's check was inside it", () => {
    expect(duplicateOf({ code: 'DUPLICATE_PLACE', existingPlaceId: 'p9', message: 'This place already exists in the selected circle' }, 'Date night'))
      .toMatchObject({ title: 'Already in Date night', existingPlaceId: 'p9' });
  });
  it('says "Already saved" when the other circle has no name', () => {
    expect(duplicateOf({ code: 'DUPLICATE_PLACE', existingPlaceId: 'p9', existingCircleId: 'c7', existingCircleName: null }, 'Date night'))
      .toEqual({ existingPlaceId: 'p9', title: 'Already saved', message: 'You already saved this place.' });
  });
  it('is not a duplicate for any other refusal', () => {
    expect(duplicateOf({ message: 'Validation error' }, 'Date night')).toBeNull();
  });
});

describe('after the save', () => {
  it('says a place waiting for review was saved privately', () => {
    expect(outcomeOf({ approvalStatus: 'pending' }, 'Coffee')).toEqual({ pending: true, toast: 'Saved privately. Others can see it once it has been reviewed.' });
  });
  it('names the circle otherwise', () => {
    expect(outcomeOf({}, 'Coffee')).toEqual({ pending: false, toast: 'Saved to Coffee' });
    expect(outcomeOf({ approvalStatus: null }, null).toast).toBe('Place saved');
  });
});

describe('the middle of my places', () => {
  it('is the median, so one far-off place does not pull it away', () => {
    expect(middleOf([{ lat: 35.1, lng: -80.9 }, { lat: 35.2, lng: -80.8 }, { lat: 48.85, lng: 2.35 }])).toEqual({ lat: 35.2, lng: -80.8 });
    expect(middleOf([{ lat: 1, lng: 1 }, { lat: 3, lng: 5 }])).toEqual({ lat: 2, lng: 3 });
    expect(middleOf([])).toBeNull();
  });
});
