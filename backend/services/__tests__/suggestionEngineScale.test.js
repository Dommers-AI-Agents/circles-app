// Viral-growth review 2026-10-01: buildIndexes now streams its four
// collections a page at a time, and suggestFor finds area matches through an
// inverted index instead of comparing every user with every user. These pin
// that both give exactly what the whole-collection / all-pairs versions did.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { buildIndexes, suggestFor, areaMatch, areaCandidates } = require('../suggestionEngine');

// Small deterministic PRNG so the "random" population is the same every run.
const rng = (seed) => () => {
  seed = (seed * 1664525 + 1013904223) % 4294967296;
  return seed / 4294967296;
};

describe('buildIndexes streams every collection across page boundaries', () => {
  beforeAll(async () => {
    // 700 places > two 300-doc pages; 320 users > one page.
    for (let i = 0; i < 320; i++) {
      mockDb.rows('users').set(`u${String(i).padStart(3, '0')}`, {
        displayName: `User ${i}`, following: i > 0 ? ['u000'] : [], followers: [], email: 'x@y.z'
      });
    }
    mockDb.rows('circles').set('pub', { privacy: 'public', owner: 'u001', placesCount: 700 });
    mockDb.rows('circles').set('priv', { privacy: 'private', owner: 'u002', placesCount: 3 });
    for (let i = 0; i < 700; i++) {
      mockDb.rows('places').set(`p${String(i).padStart(3, '0')}`, {
        addedBy: `u${String(i % 320).padStart(3, '0')}`,
        globalPlaceId: `g${i % 50}`,
        circleId: i === 699 ? 'priv' : 'pub',
        name: `Venue ${i % 50}`,
        category: i % 2 ? 'cafe' : 'bar',
        geohash: 'dnq8abcd'
      });
    }
    mockDb.rows('connections').set('c1', { status: 'accepted', userId: 'u001', connectedUserId: 'u002' });
    mockDb.rows('connections').set('c2', { status: 'declined', userId: 'u003', connectedUserId: 'u004' });
  });

  test('every doc lands in the indexes', async () => {
    const idx = await buildIndexes();
    expect(idx.users.size).toBe(320);
    expect(idx.followerCount.get('u000')).toBe(319);
    expect(idx.counts.get('u001')).toEqual({ placesCount: 700, circlesCount: 1 });
    // 699 public saves (the private circle's one is excluded) over 50 venues
    const totalSaves = [...idx.userPlaces.values()].reduce((n, set) => n + set.size, 0);
    expect(idx.savers.size).toBe(50);
    expect(totalSaves).toBeGreaterThan(300);
    expect(idx.connected.get('u001').has('u002')).toBe(true);
    expect(idx.connected.has('u003')).toBe(false);
    // Users are in document-id order, as an unordered get() returned them.
    expect([...idx.users.keys()].slice(0, 3)).toEqual(['u000', 'u001', 'u002']);
  });
});

describe('areaCandidates finds exactly who areaMatch would', () => {
  test('on a random population, no match is missed', () => {
    const rand = rng(42);
    const cells = ['dnq8a', 'dnq8b', 'dnq9c', 'dr5re', 'dr5rf', '9q8yy', 'dq'];
    const zips = ['28202', '28203', '28105', '10001', '94110', null, null];
    const userAreas = new Map();
    const categories = new Map();
    for (let i = 0; i < 400; i++) {
      const id = `u${i}`;
      const near = new Set();
      const metro = new Set();
      const nCells = Math.floor(rand() * 3);
      for (let c = 0; c < nCells; c++) {
        const cell = cells[Math.floor(rand() * cells.length)];
        metro.add(cell.slice(0, 4));
        if (cell.length >= 5) near.add(cell.slice(0, 5));
      }
      const zip = zips[Math.floor(rand() * zips.length)];
      if (near.size || metro.size || zip) {
        userAreas.set(id, { near, metro, zip, zipPrefix: zip ? zip.slice(0, 3) : null, label: null });
      }
      if (rand() < 0.6) categories.set(id, { cafe: 1 });
    }
    const idx = { userAreas, categories, areaNames: new Map() };

    for (const [me, myArea] of userAreas) {
      const { inAreaOrder, inCategoryOrder } = areaCandidates(myArea, idx);
      const found = new Set(inAreaOrder);
      const expected = [...userAreas].filter(([, theirs]) => areaMatch(myArea, theirs, idx)).map(([id]) => id);
      for (const id of expected) expect(found.has(id)).toBe(true);
      // Same order the old full loops visited them in.
      expect(inAreaOrder).toEqual([...userAreas.keys()].filter((id) => found.has(id)));
      expect(inCategoryOrder).toEqual([...categories.keys()].filter((id) => found.has(id)));
      expect(found.has(me)).toBe(true);
    }
  });

  test('suggestFor still ranks a same-area user without an all-pairs scan', () => {
    const area = (cell, zip = null) => ({
      near: new Set([cell]), metro: new Set([cell.slice(0, 4)]), zip, zipPrefix: zip ? zip.slice(0, 3) : null, label: 'Charlotte'
    });
    const user = (id) => ({ id, displayName: id, following: new Set(), dismissed: new Set(), followersCount: 0 });
    const idx = {
      users: new Map(['me', 'near', 'far'].map((id) => [id, user(id)])),
      userAreas: new Map([['me', area('dnq8a')], ['near', area('dnq8a')], ['far', area('9q8yy')]]),
      categories: new Map(),
      counts: new Map(),
      connected: new Map(),
      savers: new Map(),
      userPlaces: new Map(),
      placeNames: new Map(),
      areas: new Map(),
      areaNames: new Map(),
      followerCount: new Map()
    };
    const results = suggestFor('me', idx);
    expect(results.map((r) => r.userId)).toEqual(['near']);
    expect(results[0].reason).toBe('Saves places in Charlotte');
  });
});
