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
