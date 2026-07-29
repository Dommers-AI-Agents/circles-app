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

  // Check-in used to hand-roll its own Google-types mapping, which emitted
  // 'shopping' — not a value in the category enum, so those places fell into
  // the iOS "Other" bucket and never matched the Shopping chip. It now forwards
  // raw types to this cascade instead.
  test('check-in Google types map into the enum (store -> retail, never "shopping")', () => {
    const store = deriveCategory({ googleTypes: ['store', 'point_of_interest'] });
    expect(store.category).toBe('retail');
    expect(store.source).toBe('google');

    const mall = deriveCategory({ googleTypes: ['shopping_mall'] });
    expect(mall.category).toBe('retail');

    // The other four branches the old if-chain covered still resolve.
    expect(deriveCategory({ googleTypes: ['restaurant'] }).category).toBe('restaurant');
    expect(deriveCategory({ googleTypes: ['cafe'] }).category).toBe('cafe');
    expect(deriveCategory({ googleTypes: ['night_club'] }).category).toBe('bar');
    expect(deriveCategory({ googleTypes: ['museum'] }).category).toBe('attraction');
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
