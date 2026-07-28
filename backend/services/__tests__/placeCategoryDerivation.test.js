const { deriveCategory, categoryFromApplePoi } = require('../placeCategoryDerivation');

describe('deriveCategory cascade', () => {
  test('Google primaryType present wins', () => {
    const r = deriveCategory({ googlePrimaryType: 'coffee_shop', googleTypes: ['point_of_interest'], name: 'X' });
    // coffee_shop isn't in the map, so it falls through to types then text;
    // use a mapped primary type to assert the tier explicitly:
    const r2 = deriveCategory({ googlePrimaryType: 'cafe', name: 'X' });
    expect(r2).toEqual({ category: 'cafe', source: 'google', confidence: 0.95 });
  });

  test('legacy types[] only, first recognized entry wins', () => {
    const r = deriveCategory({ googleTypes: ['point_of_interest', 'bar', 'restaurant'] });
    expect(r.category).toBe('bar');
    expect(r.source).toBe('google');
  });

  test('unknown Google type falls through to text, else other', () => {
    const r = deriveCategory({ googleTypes: ['plumber_supply_wholesaler'], name: 'Acme Widgets' });
    expect(r.category).toBe('other');
    expect(r.source).toBe('other');
  });

  test('Apple POI category when no Google type', () => {
    const r = deriveCategory({ applePoiCategory: 'MKPOICategoryFitnessCenter' });
    expect(r).toEqual({ category: 'fitness', source: 'apple', confidence: 0.9 });
  });

  test('text inference from a venue name (the check-in/moment .other tail)', () => {
    expect(deriveCategory({ name: 'Cafe Monte' }).category).toBe('cafe');
    expect(deriveCategory({ name: 'Que Onda Tacos' }).category).toBe('restaurant');
    expect(deriveCategory({ name: "Gold's Gym" }).category).toBe('fitness');
    expect(deriveCategory({ name: 'Emmy Squared Pizza' }).source).toBe('text');
  });

  test('a place with no signal at all resolves to other', () => {
    expect(deriveCategory({})).toEqual({ category: 'other', source: 'other', confidence: 0 });
    expect(deriveCategory({ name: '   ' }).category).toBe('other');
  });

  test('deterministic tiers beat text (POI outranks a misleading name)', () => {
    // "Park Tavern" is a bar by POI even though the name contains "Park"
    const r = deriveCategory({ applePoiCategory: 'MKPOICategoryNightlife', name: 'Park Tavern' });
    expect(r.category).toBe('bar');
    expect(r.source).toBe('apple');
  });
});

describe('categoryFromApplePoi', () => {
  test('maps known raw values, others -> other', () => {
    expect(categoryFromApplePoi('MKPOICategoryRestaurant')).toBe('restaurant');
    expect(categoryFromApplePoi('MKPOICategoryEVCharger')).toBe('transport');
    expect(categoryFromApplePoi('MKPOICategoryUnknownThing')).toBe('other');
    expect(categoryFromApplePoi(null)).toBe('other');
  });
});
