// Unit tests for the suggestion ranking. These exercise `suggestFor` against
// hand-built indexes, so they need no Firestore.

jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({}) })
}));

const { suggestFor } = require('../suggestionEngine');

/** Minimal index builder so each test states only what it cares about. */
const makeIndex = ({ users = {}, places = {}, categories = {}, areas = {}, areaNames = {}, connected = {}, counts = {}, placeNames = {}, zipcodes = {}, locationLabels = {} }) => {
  const userMap = new Map();
  for (const [id, u] of Object.entries(users)) {
    userMap.set(id, {
      id,
      displayName: u.displayName || id,
      profilePicture: null,
      isVerified: false,
      following: new Set(u.following || []),
      followersCount: 0,
      dismissed: new Set(u.dismissed || []),
      geohash: null,
      zipcode: zipcodes[id] || '',
      locationLabel: locationLabels[id] || null
    });
  }

  const userPlaces = new Map();
  const savers = new Map();
  for (const [uid, placeIds] of Object.entries(places)) {
    userPlaces.set(uid, new Set(placeIds));
    for (const pid of placeIds) {
      if (!savers.has(pid)) savers.set(pid, new Set());
      savers.get(pid).add(uid);
    }
  }

  // Mirror the real indexer: follower counts are derived from the graph.
  const followerCount = new Map();
  for (const u of userMap.values()) {
    for (const followedId of u.following) {
      followerCount.set(followedId, (followerCount.get(followedId) || 0) + 1);
    }
  }

  // Mirror the indexer's location cascade: place geohashes ∪ zipcode.
  const userAreas = new Map();
  for (const [id] of userMap) {
    const near = new Set();
    const metro = new Set();
    for (const cell of Object.keys(areas[id] || {})) {
      metro.add(cell.slice(0, 4));
      if (cell.length >= 5) near.add(cell.slice(0, 5));
    }
    const zip = /^\d{5}$/.test(zipcodes[id] || '') ? zipcodes[id] : null;
    if (near.size || metro.size || zip) {
      userAreas.set(id, {
        near, metro, zip,
        zipPrefix: zip ? zip.slice(0, 3) : null,
        label: locationLabels[id] || null
      });
    }
  }

  return {
    users: userMap,
    followerCount,
    userAreas,
    counts: new Map(Object.entries(counts)),
    connected: new Map(Object.entries(connected).map(([k, v]) => [k, new Set(v)])),
    savers,
    userPlaces,
    placeNames: new Map(Object.entries(placeNames)),
    categories: new Map(Object.entries(categories)),
    areas: new Map(Object.entries(areas)),
    areaNames: new Map(Object.entries(areaNames))
  };
};

describe('suggestFor — shared saves', () => {
  it('suggests someone who saved the same places, naming a venue', () => {
    const idx = makeIndex({
      users: { me: {}, rosa: { displayName: 'Rosa' } },
      places: { me: ['g1', 'g2', 'g3'], rosa: ['g1', 'g2'] },
      placeNames: { g1: 'Café Mogador' }
    });

    const [top] = suggestFor('me', idx);
    expect(top.userId).toBe('rosa');
    expect(top.signal).toBe('sharedSaves');
    expect(top.reason).toBe('Also saved Café Mogador + 1 more');
  });

  it('ranks more overlap higher', () => {
    const idx = makeIndex({
      users: { me: {}, deep: {}, shallow: {} },
      places: { me: ['g1', 'g2', 'g3'], deep: ['g1', 'g2', 'g3'], shallow: ['g1'] },
      placeNames: { g1: 'Lucali' }
    });

    const results = suggestFor('me', idx);
    expect(results.map((r) => r.userId)).toEqual(['deep', 'shallow']);
  });

  it('says "Also saved X" without a suffix for a single shared place', () => {
    const idx = makeIndex({
      users: { me: {}, hana: {} },
      places: { me: ['g1'], hana: ['g1'] },
      placeNames: { g1: 'Lucali' }
    });

    expect(suggestFor('me', idx)[0].reason).toBe('Also saved Lucali');
  });
});

describe('suggestFor — exclusions', () => {
  const base = {
    users: { me: {}, other: {} },
    places: { me: ['g1'], other: ['g1'] },
    placeNames: { g1: 'Somewhere' }
  };

  it('never suggests yourself', () => {
    const idx = makeIndex({ ...base, places: { me: ['g1', 'g2'] } });
    expect(suggestFor('me', idx).map((r) => r.userId)).not.toContain('me');
  });

  it('never suggests someone you already follow', () => {
    const idx = makeIndex({ ...base, users: { me: { following: ['other'] }, other: {} } });
    expect(suggestFor('me', idx)).toHaveLength(0);
  });

  it('never suggests someone you dismissed', () => {
    const idx = makeIndex({ ...base, users: { me: { dismissed: ['other'] }, other: {} } });
    expect(suggestFor('me', idx)).toHaveLength(0);
  });

  it('never suggests an existing or pending connection', () => {
    const idx = makeIndex({ ...base, connected: { me: ['other'] } });
    expect(suggestFor('me', idx)).toHaveLength(0);
  });
});

describe('suggestFor — same taste', () => {
  it('fires at zero place overlap when categories and area match', () => {
    const idx = makeIndex({
      users: { me: {}, elena: { displayName: 'Elena' } },
      places: { me: ['g1'], elena: ['g9'] }, // nothing in common
      categories: { me: { cafe: 8, bar: 4 }, elena: { cafe: 6, bar: 3 } },
      areas: { me: { dr5rs: 5 }, elena: { dr5rs: 4 } },
      areaNames: { dr5rs: 'Fort Greene' },
      locationLabels: { elena: 'Fort Greene' }
    });

    const [top] = suggestFor('me', idx);
    expect(top.userId).toBe('elena');
    expect(top.signal).toBe('sameTaste');
    expect(top.reason).toBe('Saves coffee & bars in Fort Greene');
  });

  it('ignores identical taste in a different area', () => {
    const idx = makeIndex({
      users: { me: {}, faraway: {} },
      categories: { me: { cafe: 8 }, faraway: { cafe: 8 } },
      areas: { me: { dr5rs: 5 }, faraway: { u09tv: 5 } }
    });

    expect(suggestFor('me', idx)).toHaveLength(0);
  });

  it('ignores people whose taste is not actually similar', () => {
    const idx = makeIndex({
      users: { me: {}, different: {} },
      categories: { me: { cafe: 10 }, different: { fitness: 10 } },
      areas: { me: { dr5rs: 5 }, different: { dr5rs: 5 } }
    });

    // Still suggested — they're nearby, which is a real reason — but the
    // reason must not claim a shared taste that doesn't exist.
    const [top] = suggestFor('me', idx);
    expect(top.signal).toBe('sameArea');
  });
});

describe('suggestFor — location', () => {
  it('suggests someone nearby even with no shared places or taste data', () => {
    const idx = makeIndex({
      users: { me: {}, neighbor: { displayName: 'Elena' } },
      areas: { me: { dr5rs: 3 }, neighbor: { dr5rs: 2 } },
      locationLabels: { neighbor: 'Fort Greene' }
    });

    const [top] = suggestFor('me', idx);
    expect(top.userId).toBe('neighbor');
    expect(top.signal).toBe('sameArea');
    expect(top.reason).toBe('Saves places in Fort Greene');
  });

  it('matches on zipcode alone, for users who never saved a public place', () => {
    const idx = makeIndex({
      users: { me: {}, samezip: { displayName: 'Bill' } },
      zipcodes: { me: '28203', samezip: '28203' },
      locationLabels: { samezip: 'Charlotte' }
    });

    const [top] = suggestFor('me', idx);
    expect(top.userId).toBe('samezip');
    expect(top.reason).toBe('Saves places in Charlotte');
  });

  it('ranks a shared neighbourhood above a merely shared zip prefix', () => {
    const idx = makeIndex({
      users: { me: {}, close: {}, sameRegion: {} },
      areas: { me: { dr5rs: 3 }, close: { dr5rs: 3 } },
      zipcodes: { me: '28203', sameRegion: '28999' }
    });

    const results = suggestFor('me', idx);
    expect(results[0].userId).toBe('close');
  });

  it('does not match users in different areas', () => {
    const idx = makeIndex({
      users: { me: {}, faraway: {} },
      zipcodes: { me: '28203', faraway: '90210' }
    });

    expect(suggestFor('me', idx)).toHaveLength(0);
  });
});

describe('suggestFor — follow graph', () => {
  it('suggests people followed by people you follow', () => {
    const idx = makeIndex({
      users: {
        me: { following: ['dani'] },
        dani: { displayName: 'Dani', following: ['miles'] },
        miles: { displayName: 'Miles' }
      }
    });

    const [top] = suggestFor('me', idx);
    expect(top.userId).toBe('miles');
    expect(top.reason).toBe('Followed by Dani');
  });

  it('counts multiple paths and names one', () => {
    const idx = makeIndex({
      users: {
        me: { following: ['dani', 'tom'] },
        dani: { displayName: 'Dani', following: ['miles'] },
        tom: { displayName: 'Tom', following: ['miles'] },
        miles: {}
      }
    });

    expect(suggestFor('me', idx)[0].reason).toBe('Followed by Dani + 1 others');
  });
});

describe('suggestFor — hub discounting', () => {
  it('names the more informative connector, not the account everyone follows', () => {
    // `hub` is followed by everybody (the auto-follow default); `niche` by one
    // person. Both introduce `target`, but only one of them means anything.
    const crowd = {};
    for (let i = 0; i < 12; i++) crowd[`u${i}`] = { following: ['hub'] };

    const idx = makeIndex({
      users: {
        ...crowd,
        me: { following: ['hub', 'niche'] },
        hub: { displayName: 'Wesley', following: ['target'] },
        niche: { displayName: 'Dani', following: ['target'] },
        target: {}
      }
    });

    const target = suggestFor('me', idx).find((r) => r.userId === 'target');
    expect(target.reason).toBe('Followed by Dani + 1 others');
  });

  it('scores a niche-only path above a hub-only path', () => {
    const crowd = {};
    for (let i = 0; i < 12; i++) crowd[`u${i}`] = { following: ['hub'] };

    const idx = makeIndex({
      users: {
        ...crowd,
        me: { following: ['hub', 'niche'] },
        hub: { displayName: 'Wesley', following: ['viaHub'] },
        niche: { displayName: 'Dani', following: ['viaNiche'] },
        viaHub: {},
        viaNiche: {}
      }
    });

    const results = suggestFor('me', idx);
    const hubPick = results.find((r) => r.userId === 'viaHub');
    const nichePick = results.find((r) => r.userId === 'viaNiche');
    expect(nichePick.score).toBeGreaterThan(hubPick.score);
  });
});

describe('suggestFor — reason selection', () => {
  it('leads with shared saves over a weaker signal for the same person', () => {
    const idx = makeIndex({
      users: { me: { following: ['dani'] }, dani: { displayName: 'Dani', following: ['rosa'] }, rosa: {} },
      places: { me: ['g1', 'g2', 'g3'], rosa: ['g1', 'g2', 'g3'] },
      placeNames: { g1: 'Café Mogador' }
    });

    const rosa = suggestFor('me', idx).find((r) => r.userId === 'rosa');
    expect(rosa.signal).toBe('sharedSaves');
    expect(rosa.reason).toContain('Café Mogador');
  });

  it('denormalizes display fields so rendering needs no extra reads', () => {
    const idx = makeIndex({
      users: { me: {}, rosa: { displayName: 'Rosa Klein' } },
      places: { me: ['g1'], rosa: ['g1'] },
      placeNames: { g1: 'Lucali' },
      counts: { rosa: { placesCount: 38, circlesCount: 4 } }
    });

    const [top] = suggestFor('me', idx);
    expect(top.displayName).toBe('Rosa Klein');
    expect(top.placesCount).toBe(38);
    expect(top.circlesCount).toBe(4);
  });
});
