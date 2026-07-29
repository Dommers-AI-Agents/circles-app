const { deriveLocation } = require('../placeLocationDerivation');

describe('deriveLocation from address string', () => {
  test('full US address with street, city, ST ZIP, country', () => {
    const r = deriveLocation({ address: '3020 Prosperity Church Rd, Charlotte, NC 28269, United States' });
    expect(r).toMatchObject({
      state: 'North Carolina', stateCode: 'NC', city: 'Charlotte',
      cityKey: 'charlotte|NC', placed: true, source: 'address'
    });
  });

  test('city, ST (no zip, no country)', () => {
    const r = deriveLocation({ address: 'Charlotte, NC' });
    expect(r).toMatchObject({ stateCode: 'NC', city: 'Charlotte', placed: true });
  });

  test('ZIP+4 and USA suffix', () => {
    const r = deriveLocation({ address: '123 Main St, Newark, NJ 07102-1234, USA' });
    expect(r).toMatchObject({ stateCode: 'NJ', state: 'New Jersey', city: 'Newark' });
  });

  test('full state name spelled out', () => {
    const r = deriveLocation({ address: '1 Market St, San Francisco, California' });
    expect(r).toMatchObject({ stateCode: 'CA', city: 'San Francisco' });
  });

  test('forwarded neighborhood is preserved', () => {
    const r = deriveLocation({ address: 'Charlotte, NC 28203', neighborhood: 'South End' });
    expect(r).toMatchObject({ city: 'Charlotte', neighborhood: 'South End', placed: true });
  });

  test('cityKey disambiguates same city name across states', () => {
    const a = deriveLocation({ address: 'Portland, OR' });
    const b = deriveLocation({ address: 'Portland, ME' });
    expect(a.cityKey).toBe('portland|OR');
    expect(b.cityKey).toBe('portland|ME');
    expect(a.cityKey).not.toBe(b.cityKey);
  });

  test('unresolvable / international address -> Unplaced', () => {
    expect(deriveLocation({ address: '' }).placed).toBe(false);
    expect(deriveLocation({}).placed).toBe(false);
    expect(deriveLocation({ address: '10 Downing St, London, UK' }).placed).toBe(false);
    expect(deriveLocation({ address: 'Somewhere random' })).toMatchObject({ placed: false, stateCode: null });
  });

  test('does not mistake a non-state two-letter token for a state', () => {
    // "GO" is not a state; should stay Unplaced rather than false-positive
    const r = deriveLocation({ address: 'Some Place, GO 12345' });
    expect(r.placed).toBe(false);
  });
});

describe('country derivation', () => {
  const { deriveLocation, parseCountry } = require('../placeLocationDerivation');

  test('US-placed address gets US country fields', () => {
    const loc = deriveLocation({ address: '123 Main St, Charlotte, NC 28269, United States' });
    expect(loc.placed).toBe(true);
    expect(loc.countryCode).toBe('US');
    expect(loc.country).toBe('United States');
  });

  test('Canadian address: no US state, but country resolved', () => {
    const loc = deriveLocation({ address: '610 2nd Ave N, Saskatoon, SK S7K 2C7, Canada' });
    expect(loc.placed).toBe(false);
    expect(loc.stateCode).toBeNull();
    expect(loc.countryCode).toBe('CA');
    expect(loc.country).toBe('Canada');
    expect(loc.source).toBe('address');
  });

  test('Mexican address with 📍 location-hint suffix', () => {
    const loc = deriveLocation({ address: 'Carretera Transpeninsular Km 1, 23403, Mexico\n📍 6.1 mi from current location' });
    expect(loc.placed).toBe(false);
    expect(loc.countryCode).toBe('MX');
  });

  test('📍 suffix does not break US state parsing', () => {
    const loc = deriveLocation({ address: '1 Ocean Dr, Miami, FL 33139, United States\n📍 2 mi from current location' });
    expect(loc.placed).toBe(true);
    expect(loc.stateCode).toBe('FL');
    expect(loc.countryCode).toBe('US');
  });

  test('UK variants map to GB', () => {
    expect(parseCountry('10 Downing St, London, England')).toEqual({ country: 'United Kingdom', countryCode: 'GB' });
    expect(parseCountry('1 Princes St, Edinburgh, UK')).toEqual({ country: 'United Kingdom', countryCode: 'GB' });
  });

  test('unknown tail leaves country null', () => {
    const loc = deriveLocation({ address: 'Some Pier, Atlantis' });
    expect(loc.country).toBeNull();
    expect(loc.countryCode).toBeNull();
  });

  test('Canadian province code SK never mistaken for a US state', () => {
    const loc = deriveLocation({ address: '702 14 St E, Saskatoon, SK S7N 0P7, Canada' });
    expect(loc.stateCode).toBeNull();
  });
});
