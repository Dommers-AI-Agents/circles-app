const {
  mergeSummaries,
  summarizeCirclePlaces,
  buildCityVenues,
  densestNeighborhood
} = require('../../services/browseAggregation');

const P = (over) => ({ id: over.id || Math.random().toString(36).slice(2), ...over });

describe('mergeSummaries (network tree from per-circle summaries)', () => {
  test('sums density counts across circles into a State→City tree', () => {
    const summaries = [
      { cityCounts: { 'charlotte|NC': 12, 'durham|NC': 3 },
        cityMeta: { 'charlotte|NC': { city: 'Charlotte', stateCode: 'NC', state: 'North Carolina' },
                    'durham|NC': { city: 'Durham', stateCode: 'NC', state: 'North Carolina' } },
        unplacedCount: 2 },
      { cityCounts: { 'charlotte|NC': 8, 'newark|NJ': 40 },
        cityMeta: { 'charlotte|NC': { city: 'Charlotte', stateCode: 'NC', state: 'North Carolina' },
                    'newark|NJ': { city: 'Newark', stateCode: 'NJ', state: 'New Jersey' } } }
    ];
    const tree = mergeSummaries(summaries);
    const nc = tree.states.find(s => s.stateCode === 'NC');
    expect(nc.count).toBe(23);                       // 12+3 + 8
    expect(nc.cities.find(c => c.cityKey === 'charlotte|NC').count).toBe(20); // 12+8
    expect(tree.states[0].stateCode).toBe('NJ');     // 40 > 23 -> NJ sorts first
    expect(tree.states.find(s => s.stateCode === 'NJ').count).toBe(40);
    expect(tree.unplaced).toEqual({ cityKey: '__unplaced__', count: 2 });
  });

  test('empty / no summaries -> empty tree, no unplaced key', () => {
    expect(mergeSummaries([])).toEqual({ states: [] });
    expect(mergeSummaries([null, {}]).states).toEqual([]);
  });
});

describe('summarizeCirclePlaces', () => {
  test('counts a circle\'s placed saves by city, tracks unplaced', () => {
    const s = summarizeCirclePlaces([
      P({ cityKey: 'charlotte|NC', city: 'Charlotte', stateCode: 'NC', state: 'North Carolina' }),
      P({ cityKey: 'charlotte|NC', city: 'Charlotte', stateCode: 'NC', state: 'North Carolina' }),
      P({ /* unplaced */ }),
      P({ cityKey: 'x|NC', stateCode: 'NC', deletedAt: '2026-01-01' }) // deleted -> ignored
    ]);
    expect(s.cityCounts['charlotte|NC']).toBe(2);
    expect(s.unplacedCount).toBe(1);
    expect(s.cityCounts['x|NC']).toBeUndefined();
  });
});

describe('buildCityVenues (network city view)', () => {
  test('dedupes to venues; collects savers + circles + rating; savedByMe', () => {
    const userById = new Map([
      ['u1', { id: 'u1', displayName: 'Wes', profilePicture: 'w.jpg' }],
      ['u2', { id: 'u2', displayName: 'Brittany', profilePicture: null }]
    ]);
    const circleNameById = new Map([['c1', 'Charlotte NC'], ['c2', 'Faves']]);
    const ratingByVenue = new Map([['v1', 4.5]]);
    const venues = buildCityVenues([
      P({ globalPlaceId: 'v1', name: 'Fresh Monkee', category: 'cafe', circleId: 'c1', addedBy: 'u1' }),
      P({ globalPlaceId: 'v1', name: 'Fresh Monkee', category: 'cafe', circleId: 'c2', addedBy: 'u2' })
    ], { userById, circleNameById, ratingByVenue, currentUserId: 'u1' });

    expect(venues).toHaveLength(1);
    const v = venues[0];
    expect(v.rating).toBe(4.5);
    expect(v.savers.map(s => s.name).sort()).toEqual(['Brittany', 'Wes']);
    expect(v.circles.map(c => c.name).sort()).toEqual(['Charlotte NC', 'Faves']);
    expect(v.savedByMe).toBe(true);
    expect(v).not.toHaveProperty('_saverIds');
  });
});

describe('densestNeighborhood', () => {
  test('most common neighborhood, or null when sparse', () => {
    expect(densestNeighborhood([
      { neighborhood: 'South End' }, { neighborhood: 'South End' }, { neighborhood: 'SouthPark' }
    ])).toEqual({ neighborhood: 'South End', count: 2 });
    expect(densestNeighborhood([{ neighborhood: null }, {}])).toBeNull();
  });
});
