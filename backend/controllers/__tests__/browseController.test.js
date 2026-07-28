const { buildLocationTree, buildCityVenues, densestNeighborhood } = require('../../services/browseAggregation');

const P = (over) => ({ id: over.id || Math.random().toString(36).slice(2), ...over });

describe('buildLocationTree', () => {
  const places = [
    P({ globalPlaceId: 'v1', stateCode: 'NC', state: 'North Carolina', city: 'Charlotte', cityKey: 'charlotte|NC' }),
    // same venue saved to a 2nd circle -> still ONE pin
    P({ globalPlaceId: 'v1', stateCode: 'NC', state: 'North Carolina', city: 'Charlotte', cityKey: 'charlotte|NC' }),
    P({ globalPlaceId: 'v2', stateCode: 'NC', state: 'North Carolina', city: 'Charlotte', cityKey: 'charlotte|NC' }),
    P({ globalPlaceId: 'v3', stateCode: 'NC', state: 'North Carolina', city: 'Durham', cityKey: 'durham|NC' }),
    P({ globalPlaceId: 'v4', stateCode: 'NJ', state: 'New Jersey', city: 'Newark', cityKey: 'newark|NJ' }),
    P({ globalPlaceId: 'v5' }) // Unplaced (no stateCode)
  ];

  test('counts unique venues per state and city', () => {
    const tree = buildLocationTree(places);
    const nc = tree.states.find(s => s.stateCode === 'NC');
    expect(nc.count).toBe(3);                    // v1, v2, v3 (v1 duplicate collapsed)
    const charlotte = nc.cities.find(c => c.cityKey === 'charlotte|NC');
    expect(charlotte.count).toBe(2);             // v1, v2
  });

  test('states sorted by count desc; unplaced surfaced', () => {
    const tree = buildLocationTree(places);
    expect(tree.states[0].stateCode).toBe('NC'); // 3 > 1
    expect(tree.unplaced).toEqual({ cityKey: '__unplaced__', count: 1 });
  });

  test('no unplaced key when everything is placed', () => {
    const tree = buildLocationTree([P({ globalPlaceId: 'v1', stateCode: 'CA', state: 'California', city: 'LA', cityKey: 'la|CA' })]);
    expect(tree.unplaced).toBeUndefined();
  });
});

describe('buildCityVenues', () => {
  test('one venue, multiple source-circle chips', () => {
    const names = new Map([['c1', 'Charlotte NC'], ['c2', 'Want to go']]);
    const venues = buildCityVenues([
      P({ globalPlaceId: 'v1', name: 'Emmy Squared', category: 'restaurant', circleId: 'c1', neighborhood: 'South End' }),
      P({ globalPlaceId: 'v1', name: 'Emmy Squared', category: 'restaurant', circleId: 'c2', neighborhood: 'South End' })
    ], names);
    expect(venues).toHaveLength(1);
    expect(venues[0].circles.map(c => c.name).sort()).toEqual(['Charlotte NC', 'Want to go']);
    expect(venues[0]).not.toHaveProperty('_circleIds');
  });
});

describe('densestNeighborhood', () => {
  test('returns the most common neighborhood, or null when sparse', () => {
    expect(densestNeighborhood([
      { neighborhood: 'South End' }, { neighborhood: 'South End' }, { neighborhood: 'SouthPark' }
    ])).toEqual({ neighborhood: 'South End', count: 2 });
    expect(densestNeighborhood([{ neighborhood: null }, {}])).toBeNull();
  });
});
