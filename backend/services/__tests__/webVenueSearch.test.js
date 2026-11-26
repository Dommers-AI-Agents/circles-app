// Venue search for the web app's Add Place: Photon (OpenStreetMap) features
// become the app's venue results. No network: fetch is always a stub.
const {
  searchVenues, mapFeatures, mapFeature, nearestFirst, categoryFor, addressLine, cacheKey, originOf, clearCache,
  USER_AGENT, CACHE_TTL_MS
} = require('../webVenueSearch');
const { AUTO_CATEGORY_IDS } = require('../../config/placeCategories');

const feature = (props, coordinates = [-80.8473555, 35.1734015]) => ({
  type: 'Feature',
  properties: { osm_type: 'N', osm_id: 11073781554, osm_key: 'amenity', osm_value: 'cafe', ...props },
  geometry: { type: 'Point', coordinates }
});

const amelies = feature({
  name: "Amelie's French Bakery & Café", housenumber: '4321', street: 'Park Road', city: 'Charlotte',
  county: 'Mecklenburg', state: 'North Carolina', country: 'United States', postcode: '28209', countrycode: 'US'
});

const answering = (json, status = 200) => jest.fn(async () => ({ ok: status === 200, status, json: async () => json }));

beforeEach(() => {
  clearCache();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => jest.restoreAllMocks());

describe('categoryFor', () => {
  it('maps OSM tags to the app categories', () => {
    expect(categoryFor('amenity', 'restaurant')).toBe('restaurant');
    expect(categoryFor('amenity', 'fast_food')).toBe('restaurant');
    expect(categoryFor('amenity', 'cafe')).toBe('cafe');
    expect(categoryFor('amenity', 'bar')).toBe('bar');
    expect(categoryFor('amenity', 'pub')).toBe('bar');
    expect(categoryFor('shop', 'books')).toBe('retail');
    expect(categoryFor('shop', 'hairdresser')).toBe('service');
    expect(categoryFor('shop', 'coffee')).toBe('cafe');
    expect(categoryFor('shop', 'bakery')).toBe('cafe');
    expect(categoryFor('tourism', 'hotel')).toBe('hotel');
    expect(categoryFor('tourism', 'attraction')).toBe('attraction');
    expect(categoryFor('tourism', 'museum')).toBe('attraction');
    expect(categoryFor('leisure', 'fitness_centre')).toBe('fitness');
    expect(categoryFor('leisure', 'park')).toBe('outdoor');
    expect(categoryFor('leisure', 'bowling_alley')).toBe('entertainment');
    expect(categoryFor('amenity', 'bank')).toBe('finance');
    expect(categoryFor('amenity', 'hospital')).toBe('healthcare');
    expect(categoryFor('craft', 'brewery')).toBe('bar');
  });

  it("falls back to 'other' for anything it doesn't know", () => {
    expect(categoryFor('amenity', 'bench')).toBe('other');
    expect(categoryFor('leisure', 'something_new')).toBe('other');
    expect(categoryFor('building', 'yes')).toBe('other');
    expect(categoryFor(undefined, undefined)).toBe('other');
  });

  it('only ever gives a category the app may infer (never home or work)', () => {
    const tags = [['amenity', 'restaurant'], ['amenity', 'cafe'], ['amenity', 'pub'], ['amenity', 'cinema'], ['amenity', 'dentist'],
      ['amenity', 'school'], ['amenity', 'bank'], ['amenity', 'fuel'], ['amenity', 'post_office'], ['amenity', 'gym'], ['amenity', 'marketplace'],
      ['shop', 'anything'], ['shop', 'beauty'], ['tourism', 'hostel'], ['tourism', 'zoo'], ['tourism', 'camp_site'], ['leisure', 'dance'],
      ['leisure', 'garden'], ['leisure', 'stadium'], ['craft', 'carpenter'], ['historic', 'castle'], ['natural', 'peak'],
      ['healthcare', 'physiotherapist'], ['office', 'lawyer'], ['aeroway', 'aerodrome'], ['railway', 'station'], ['public_transport', 'platform'],
      ['building', 'house'], ['office', 'company']];
    tags.forEach(([key, value]) => expect(AUTO_CATEGORY_IDS).toContain(categoryFor(key, value)));
  });
});

describe('addressLine', () => {
  it('writes one line, street first', () => {
    expect(addressLine(amelies.properties)).toBe('4321 Park Road, Charlotte, North Carolina 28209');
  });
  it('names the country outside the US', () => {
    expect(addressLine({ street: 'Rue de Rivoli', housenumber: '99', city: 'Paris', postcode: '75001', country: 'France', countrycode: 'FR' }))
      .toBe('99 Rue de Rivoli, Paris, 75001, France');
  });
  it('uses what there is, without repeating itself', () => {
    expect(addressLine({ city: 'Charlotte', state: 'North Carolina', countrycode: 'US' })).toBe('Charlotte, North Carolina');
    expect(addressLine({ locality: 'Berlin', city: 'Berlin', countrycode: 'DE', country: 'Germany' })).toBe('Berlin, Germany');
    expect(addressLine({})).toBe('');
  });
});

describe('mapFeature', () => {
  it('gives the shape a save needs', () => {
    expect(mapFeature(amelies)).toEqual({
      name: "Amelie's French Bakery & Café",
      address: '4321 Park Road, Charlotte, North Carolina 28209',
      location: { type: 'Point', coordinates: [-80.8473555, 35.1734015] },
      category: 'cafe',
      source: 'osm',
      osmId: 'N11073781554'
    });
  });
  it('drops features with no name, no id, bad coordinates, and roads and towns', () => {
    expect(mapFeature(feature({ street: 'Park Road' }))).toBeNull();
    expect(mapFeature(feature({ name: '   ' }))).toBeNull();
    expect(mapFeature(feature({ name: 'Nowhere', osm_id: undefined }))).toBeNull();
    expect(mapFeature(feature({ name: 'Park Road', osm_key: 'highway', osm_value: 'secondary' }))).toBeNull();
    expect(mapFeature(feature({ name: 'Charlotte', osm_key: 'place', osm_value: 'city' }))).toBeNull();
    expect(mapFeature(feature({ name: 'Odd' }, [-80.8, 135]))).toBeNull();
    expect(mapFeature({ properties: { name: 'No geometry', osm_id: 1 } })).toBeNull();
    expect(mapFeature(null)).toBeNull();
  });
  it('falls back to the coordinates when OSM has no address at all', () => {
    expect(mapFeature(feature({ name: 'Lone Spot' })).address).toBe('35.17340, -80.84736');
  });
});

describe('mapFeatures', () => {
  it('keeps one result per OSM object, with the tag that says what it is', () => {
    const asShop = feature({ ...amelies.properties, osm_key: 'shop', osm_value: 'bakery' });
    const venues = mapFeatures({ features: [amelies, asShop] });
    expect(venues).toHaveLength(1);
    expect(venues[0].category).toBe('cafe');

    const unknownFirst = feature({ name: 'Mystery', osm_id: 7, osm_key: 'building', osm_value: 'yes' });
    const thenBar = feature({ name: 'Mystery', osm_id: 7, osm_key: 'amenity', osm_value: 'bar' });
    expect(mapFeatures({ features: [unknownFirst, thenBar] })).toEqual([expect.objectContaining({ osmId: 'N7', category: 'bar' })]);
  });
  it('survives an empty or odd answer', () => {
    expect(mapFeatures({})).toEqual([]);
    expect(mapFeatures(null)).toEqual([]);
    expect(mapFeatures({ features: [feature({}), amelies] })).toHaveLength(1);
  });
});

describe('nearestFirst', () => {
  const at = (name, lat, lng) => ({ name, location: { type: 'Point', coordinates: [lng, lat] } });
  const greece = at('Amelies (Thessaloniki)', 40.63, 22.94);
  const uptown = at('Amelie’s (Uptown)', 35.2242, -80.8452);
  const noda = at('Amelie’s (NoDa)', 35.2466, -80.8034);
  const rockHill = at("Amelie's (Rock Hill)", 34.925, -81.026);

  it('puts the places near the person first, however Photon ranked them', () => {
    const names = nearestFirst([greece, rockHill, noda, uptown], { lat: 35.2271, lng: -80.8431 }).map((v) => v.name);
    expect(names).toEqual(['Amelie’s (Uptown)', 'Amelie’s (NoDa)', "Amelie's (Rock Hill)", 'Amelies (Thessaloniki)']);
  });

  it('keeps only the nearest when there are more than the limit', () => {
    expect(nearestFirst([greece, rockHill, noda, uptown], { lat: 35.2271, lng: -80.8431 }, 2).map((v) => v.name))
      .toEqual(['Amelie’s (Uptown)', 'Amelie’s (NoDa)']);
  });

  it("keeps Photon's order without a location", () => {
    expect(nearestFirst([greece, rockHill, noda], null, 2)).toEqual([greece, rockHill]);
  });
});

describe('cacheKey / originOf', () => {
  it('ignores case and spacing, and rounds the location', () => {
    expect(cacheKey("  Amelie's   Bakery ", { lat: 35.2271, lng: -80.8431 })).toBe("amelie's bakery|35.23,-80.84");
    expect(cacheKey('amelie', null)).toBe('amelie|anywhere');
  });
  it('reads a location only when both numbers are real', () => {
    expect(originOf('35.2', '-80.8')).toEqual({ lat: 35.2, lng: -80.8 });
    expect(originOf('35.2', undefined)).toBeNull();
    expect(originOf('abc', '-80.8')).toBeNull();
    expect(originOf('95', '-80.8')).toBeNull();
  });
});

describe('searchVenues', () => {
  it('asks Photon politely and maps the answer', async () => {
    const fetchStub = answering({ features: [amelies] });
    const venues = await searchVenues({ q: " Amelie's ", lat: '35.2271', lng: '-80.8431' }, { fetch: fetchStub });
    expect(venues).toEqual([expect.objectContaining({ name: "Amelie's French Bakery & Café", source: 'osm' })]);
    const [url, options] = fetchStub.mock.calls[0];
    const asked = new URL(url);
    expect(asked.origin + asked.pathname).toBe('https://photon.komoot.io/api/');
    expect(asked.searchParams.get('q')).toBe("Amelie's");
    expect(asked.searchParams.get('lat')).toBe('35.2271');
    expect(asked.searchParams.get('lon')).toBe('-80.8431');
    // Asked for more than it keeps, so the nearest can be picked
    expect(asked.searchParams.get('limit')).toBe('25');
    expect(asked.searchParams.get('lang')).toBe('en');
    expect(options.headers['User-Agent']).toBe(USER_AGENT);
    expect(USER_AGENT).not.toMatch(/@/);
    expect(options.signal).toBeDefined();
  });

  it('leaves the location out when there is none', async () => {
    const fetchStub = answering({ features: [] });
    await searchVenues({ q: 'optimist hall' }, { fetch: fetchStub });
    const asked = new URL(fetchStub.mock.calls[0][0]);
    expect(asked.searchParams.has('lat')).toBe(false);
    expect(asked.searchParams.has('lon')).toBe(false);
    expect(asked.searchParams.get('limit')).toBe('10');
  });

  it('refuses fewer than 3 letters without calling out', async () => {
    const fetchStub = answering({ features: [] });
    await expect(searchVenues({ q: ' ab ' }, { fetch: fetchStub })).rejects.toMatchObject({ status: 400, code: 'QUERY_TOO_SHORT' });
    await expect(searchVenues({}, { fetch: fetchStub })).rejects.toMatchObject({ status: 400, code: 'QUERY_TOO_SHORT' });
    expect(fetchStub).not.toHaveBeenCalled();
  });

  it('answers the same search from memory for 10 minutes', async () => {
    const fetchStub = answering({ features: [amelies] });
    let now = 1000000;
    const deps = { fetch: fetchStub, now: () => now };
    await searchVenues({ q: 'amelie', lat: 35.2271, lng: -80.8431 }, deps);
    // Same words, a few blocks away: the same answer
    await searchVenues({ q: 'AMELIE', lat: 35.2269, lng: -80.8433 }, deps);
    expect(fetchStub).toHaveBeenCalledTimes(1);
    // Somewhere else: a new question
    await searchVenues({ q: 'amelie', lat: 40.7, lng: -74.0 }, deps);
    expect(fetchStub).toHaveBeenCalledTimes(2);
    now += CACHE_TTL_MS + 1;
    await searchVenues({ q: 'amelie', lat: 35.2271, lng: -80.8431 }, deps);
    expect(fetchStub).toHaveBeenCalledTimes(3);
  });

  it('says the search is unavailable when Photon fails, and does not remember the failure', async () => {
    const failing = jest.fn(async () => { throw new Error('The operation was aborted due to timeout'); });
    await expect(searchVenues({ q: 'amelie' }, { fetch: failing })).rejects.toMatchObject({ status: 502, code: 'VENUE_SEARCH_UNAVAILABLE' });
    await expect(searchVenues({ q: 'amelie' }, { fetch: answering({}, 503) })).rejects.toMatchObject({ status: 502, code: 'VENUE_SEARCH_UNAVAILABLE' });
    const working = answering({ features: [amelies] });
    await expect(searchVenues({ q: 'amelie' }, { fetch: working })).resolves.toHaveLength(1);
    expect(working).toHaveBeenCalledTimes(1);
  });
});
