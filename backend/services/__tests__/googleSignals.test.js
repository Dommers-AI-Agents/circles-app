// Every free field from Google's details, and categories that follow it (2026-10-29).
const fields = require('../googlePlaceFields');
const { refineCategory, classifyFromGoogle, googleReclassification } = require('../placeCategoryDerivation');

// What Google returns for a place like Frenchy's Sip and Shop
const FRENCHYS = {
  name: "Frenchy's Sip and Shop", types: ['bar', 'restaurant', 'food', 'point_of_interest', 'establishment'],
  serves_wine: true, serves_beer: true, serves_dinner: true, serves_lunch: false, dine_in: true,
  business_status: 'OPERATIONAL', url: 'https://maps.google.com/?cid=1', utc_offset: -240, wheelchair_accessible_entrance: true
};

describe('the field list', () => {
  test('every details call asks for types and the serves_* answers it already pays for, never reviews', () => {
    expect(fields.DETAILS_ALL).toEqual(expect.arrayContaining(['types', 'serves_wine', 'serves_dinner', 'business_status', 'utc_offset', 'website', 'rating']));
    expect(fields.DETAILS_ALL).not.toContain('utc_offset_minutes');
    expect(fields.DETAILS_ALL).not.toContain('reviews');
    expect(new Set(fields.DETAILS_ALL).size).toBe(fields.DETAILS_ALL.length);
  });
  test('signals keep what Google said and null what it did not', () => {
    const s = fields.googleSignals(FRENCHYS);
    expect(s.googleTypes[0]).toBe('bar');
    expect(s.serves).toEqual({ breakfast: null, brunch: null, lunch: false, dinner: true, beer: true, wine: true, vegetarian: null });
    expect(s.utcOffsetMinutes).toBe(-240);
    const u = fields.venueSignalUpdates(s);
    expect(u['googleData.serves'].wine).toBe(true);
    expect(u['googleData.businessStatus']).toBe('OPERATIONAL');
    expect(u.googleTypes).toEqual(FRENCHYS.types);
  });
});

describe('categories from Google', () => {
  const sig = (d) => { const s = fields.googleSignals(d); return { googleTypes: s.googleTypes, serves: s.serves, dineIn: s.dineIn, name: d.name }; };

  test("Frenchy's: a restaurant with a wine bar (and a shop), not a bar", () => {
    expect(classifyFromGoogle(sig(FRENCHYS))).toMatchObject({ category: 'restaurant', subcategory: 'Wine bar & shop', source: 'google' });
  });
  test("Google's real answer for Frenchy's (bar + food, wine, dine-in) reads as a restaurant with a wine bar", () => {
    const real = { name: "Frenchy's Sip and Shop", types: ['bar', 'establishment', 'food', 'point_of_interest'], serves_wine: true, serves_beer: true, dine_in: true };
    expect(classifyFromGoogle(sig(real))).toMatchObject({ category: 'restaurant', subcategory: 'Wine bar & shop' });
  });
  test('a bar that serves dinner is a restaurant & bar; a plain bar stays a bar', () => {
    expect(refineCategory({ category: 'bar', googleTypes: ['bar'], serves: { dinner: true, beer: true }, name: "Murphy's" })).toEqual({ category: 'restaurant', subcategory: 'Bar' });
    expect(refineCategory({ category: 'bar', googleTypes: ['bar'], serves: { beer: true }, name: 'The Dive' })).toEqual({ category: 'bar', subcategory: null });
  });
  test('second labels: brewery, nightclub, bakery', () => {
    expect(refineCategory({ category: 'bar', googleTypes: ['bar'], name: 'Wooden Robot Brewery' }).subcategory).toBe('Brewery');
    expect(refineCategory({ category: 'bar', googleTypes: ['night_club', 'bar'], name: 'Neon' }).subcategory).toBe('Nightclub');
    expect(refineCategory({ category: 'cafe', googleTypes: ['cafe', 'bakery'], name: 'Amelie' }).subcategory).toBe('Bakery');
  });
  test('no types, no Google answer', () => {
    expect(classifyFromGoogle({ googleTypes: [] })).toBeNull();
    expect(classifyFromGoogle({ googleTypes: ['point_of_interest', 'establishment'] })).toBeNull();
  });
  test("Google outranks the phone's guess; an owner's or admin's choice stands", () => {
    const venue = { name: "Frenchy's Sip and Shop", category: 'bar', categorySource: 'client' };
    expect(googleReclassification(venue, sig(FRENCHYS))).toMatchObject({ category: 'restaurant', subcategory: 'Wine bar & shop', categorySource: 'google', categoryBefore: 'bar' });
    expect(googleReclassification({ ...venue, categorySource: 'manual' }, sig(FRENCHYS))).toBeNull();
    const done = { ...venue, category: 'restaurant', subcategory: 'Wine bar & shop', categorySource: 'google' };
    expect(googleReclassification(done, sig(FRENCHYS))).toBeNull();
  });

  test("generic types ('store', 'food') never overrule a category we have", () => {
    const amph = { name: 'Skyla Credit Union Amphitheatre', category: 'attraction', categorySource: 'google' };
    expect(googleReclassification(amph, { googleTypes: ['establishment', 'point_of_interest', 'store'] })).toBeNull();
    // ...but they still classify a venue that has nothing
    expect(googleReclassification({ name: 'X', category: 'other' }, { googleTypes: ['store', 'establishment'] })).toMatchObject({ category: 'retail' });
    // and a specific type still wins: Community Matters Cafe was saved as a restaurant
    expect(googleReclassification({ name: 'Community Matters Cafe', category: 'restaurant', categorySource: 'client' },
      { googleTypes: ['cafe', 'establishment', 'food'] })).toMatchObject({ category: 'cafe' });
  });
});
