const { scanLocationCheck } = require('../scanLocation');

// Store on Camden Rd, Charlotte
const venue = { location: { lat: 35.2161, lng: -80.8580 } };
const at = (dLat, extra = {}) => ({ location: { latitude: 35.2161 + dLat, longitude: -80.8580, ...extra } });

describe('scanLocationCheck', () => {
  test('a fix at the store, or in its parking lot, is near', () => {
    expect(scanLocationCheck(at(0), venue)).toBe('near');
    expect(scanLocationCheck(at(0.002), venue)).toBe('near'); // ~220 m
  });

  test('a fix across town is far', () => {
    expect(scanLocationCheck(at(0.05), venue)).toBe('far'); // ~5.5 km
  });

  test("a poor indoor fix widens the reach so a regular isn't turned away", () => {
    expect(scanLocationCheck(at(0.004, { accuracy: 200 }), venue)).toBe('near'); // ~445 m, ±200
    expect(scanLocationCheck(at(0.004), venue)).toBe('far');
    expect(scanLocationCheck(at(0.008, { accuracy: 500 }), venue)).toBe('far'); // ~890 m, ±500
  });

  test('a fix too vague to judge (Approximate Location, a failed GPS) is unknown and earns', () => {
    expect(scanLocationCheck(at(0.05, { accuracy: 501 }), venue)).toBe('unknown');
    expect(scanLocationCheck(at(0.05, { accuracy: 3000 }), venue)).toBe('unknown');
  });

  test("the App Clip's Apple check wins either way", () => {
    expect(scanLocationCheck({ atStore: false, ...at(0) }, venue)).toBe('far');
    expect(scanLocationCheck({ atStore: true }, venue)).toBe('near');
  });

  test('location off still counts as off (earns, marked); nothing at all is unknown', () => {
    expect(scanLocationCheck({ locationOff: true }, venue)).toBe('off');
    expect(scanLocationCheck({}, venue)).toBe('unknown');
    expect(scanLocationCheck(undefined, venue)).toBe('unknown');
  });

  test('a store with no map point cannot be judged', () => {
    expect(scanLocationCheck(at(0.05), { location: null })).toBe('unknown');
  });

  test('reads GeoJSON store points too', () => {
    expect(scanLocationCheck(at(0), { location: { type: 'Point', coordinates: [-80.8580, 35.2161] } })).toBe('near');
  });
});
