const { nameKey, streetNumber, nameOverlap, bestMatch } = require('../matcher');
const { toRecord } = require('../directorySync');
const { searchUrl, withRef } = require('../linkService');

// Uptown Charlotte
const HERE = { lat: 35.2271, lng: -80.8431 };
const offset = (metersNorth) => ({ lat: HERE.lat + metersNorth / 111320, lng: HERE.lng });
const candidate = (name, address, meters = 0, rid = 1) => ({ rid, name, address, ...offset(meters), profileUrl: `https://www.opentable.com/r/${rid}` });

describe('OpenTable matcher', () => {
  test('names reduce to their meaningful words', () => {
    expect(nameKey("The Capital Grille")).toBe('capital grille');
    expect(nameKey('Cork & Cap')).toBe('cap cork');
    expect(nameKey("Harris' Restaurant")).toBe('harris');
    expect(streetNumber('201 N Tryon St, Charlotte')).toBe('201');
    expect(streetNumber('N Tryon St')).toBeNull();
  });

  test('matches the same restaurant despite "The", "&" and suffixes', () => {
    const place = { name: 'Capital Grille', address: '201 N Tryon St', ...HERE };
    const m = bestMatch(place, [candidate('The Capital Grille - Charlotte', '201 N. Tryon St.', 20, 7)]);
    expect(m && m.candidate.rid).toBe(7);
  });

  test('a chain with the location after a dash still matches (North Italia, 2026-09-29)', () => {
    const place = { name: 'North Italia', address: '1414 S Tryon St, Charlotte, NC, 28203', ...HERE };
    const m = bestMatch(place, [candidate('North Italia - Charlotte - South End', '1414 S Tryon St. Suite 140', 50, 9)]);
    expect(m && m.candidate.rid).toBe(9);
  });

  test('no match when the same name is 2 km away', () => {
    const place = { name: 'Capital Grille', address: '201 N Tryon St', ...HERE };
    expect(bestMatch(place, [candidate('The Capital Grille', '201 N Tryon St', 2000)])).toBeNull();
  });

  test('no match for a different restaurant next door', () => {
    const place = { name: 'Midnight Diner', address: '115 E Carson Blvd', ...HERE };
    expect(bestMatch(place, [candidate('Mortons The Steakhouse', '227 W Trade St', 30)])).toBeNull();
  });

  test('a short name does not grab a longer, different one', () => {
    expect(nameOverlap('Pizza', 'Pizza Hut Express')).toBe(0);
    const place = { name: 'Pizza', address: '', ...HERE };
    expect(bestMatch(place, [candidate('Pizza Hut Express', '', 10)])).toBeNull();
  });

  test('street numbers that disagree block a match', () => {
    const place = { name: 'Fahrenheit', address: '222 S Caldwell St', ...HERE };
    expect(bestMatch(place, [candidate('Fahrenheit', '500 S Caldwell St', 40)])).toBeNull();
  });

  test('picks the closer of two same-name candidates', () => {
    const place = { name: 'Starbucks', address: '', ...HERE };
    const m = bestMatch(place, [candidate('Starbucks', '', 120, 1), candidate('Starbucks', '', 15, 2)]);
    expect(m.candidate.rid).toBe(2);
  });
});

describe('directory records', () => {
  test('keeps what the link needs and upgrades links to https', () => {
    const r = toRecord({
      rid: 10, name: "Harris'", address: '2100 Van Ness Avenue', address2: '', city: 'San Francisco', state: 'CA', country: 'US',
      latitude: '37.7950668', longitude: '-122.4229237', postal_code: '94109',
      natural_profile_url: 'http://www.opentable.com/r/harris-san-francisco'
    });
    expect(r.profileUrl).toBe('https://www.opentable.com/r/harris-san-francisco');
    expect(r.geohash).toMatch(/^9q8/);
    expect(r.nameKey).toBe('harris');
    expect(r.hash).toHaveLength(40);
  });

  test('skips items without coordinates', () => {
    expect(toRecord({ rid: 1, name: 'x', latitude: '', longitude: '' })).toBeNull();
    expect(toRecord({ rid: 1, name: 'x', latitude: '0', longitude: '0' })).toBeNull();
  });
});

describe('links', () => {
  const saved = process.env.OPENTABLE_REF_ID;
  afterEach(() => { process.env.OPENTABLE_REF_ID = saved; });

  test('search fallback carries name and location', () => {
    const u = new URL(searchUrl({ name: 'P&J Cafe', lat: 35.2, lng: -80.8 }));
    expect(u.searchParams.get('term')).toBe('P&J Cafe');
    expect(u.searchParams.get('latitude')).toBe('35.2');
    expect(u.searchParams.get('covers')).toBe('2');
  });

  test('referral id is added only when set', () => {
    delete process.env.OPENTABLE_REF_ID;
    expect(withRef('https://www.opentable.com/r/x')).toBe('https://www.opentable.com/r/x');
    process.env.OPENTABLE_REF_ID = '1234';
    expect(withRef('https://www.opentable.com/r/x')).toBe('https://www.opentable.com/r/x?ref=1234');
    expect(withRef('https://www.opentable.com/s?term=a')).toBe('https://www.opentable.com/s?term=a&ref=1234');
  });
});
