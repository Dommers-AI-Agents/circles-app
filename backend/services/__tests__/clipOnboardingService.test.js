// The App Clip's first favorites and its onboarding summary (2026-11-24)
jest.mock('../ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => null }));
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { saveFavoritesForClip, favoriteBody, validPick, recordClipOnboarding } = require('../clipOnboardingService');

const user = { uid: 'u1' };
const circle = async () => ({ id: 'fav1' });
const pick = (name, extra = {}) => ({ name, address: '1 Main St, Charlotte, NC', lat: 35.2, lng: -80.8, category: 'restaurant', ...extra });

test('a pick becomes the core save body, with its Apple signals', () => {
  const body = favoriteBody(pick('Haberdish', { applePoiCategory: 'MKPOICategoryRestaurant', applePlaceId: 'I123', phone: '704', clientSaveId: 'c1' }), 'fav1');
  expect(body).toMatchObject({
    circleId: 'fav1', name: 'Haberdish', address: '1 Main St, Charlotte, NC', category: 'restaurant',
    location: { type: 'Point', coordinates: [-80.8, 35.2] },
    applePoiCategory: 'MKPOICategoryRestaurant', applePlaceId: 'I123', appleMatched: true, phone: '704', clientSaveId: 'c1'
  });
  expect(body.website).toBeUndefined();
});

test('an unknown category becomes other, and a bare POI gets its spot as the address', () => {
  const body = favoriteBody({ name: 'Trailhead', lat: 35.1, lng: -80.9, category: 'hiking' }, 'c');
  expect(body.category).toBe('other');
  expect(body.address).toBe('35.10000, -80.90000');
});

test('only real picks count: a name and coordinates on Earth', () => {
  expect(validPick(pick('Ok'))).toBe(true);
  expect(validPick({ name: 'Ok', location: { lat: 35.2, lng: -80.8 } })).toBe(true);
  expect(validPick({ name: '', lat: 35.2, lng: -80.8 })).toBe(false);
  expect(validPick({ name: 'Nowhere', lat: 0, lng: 0 })).toBe(false);
  expect(validPick({ name: 'Off', lat: 95, lng: 10 })).toBe(false);
  expect(validPick(null)).toBe(false);
});

test('saves up to three picks through the core save and adds up the coins', async () => {
  const bodies = [];
  let after = 0;
  const out = await saveFavoritesForClip(user, [pick('A'), pick('B'), pick('C'), pick('D')], {
    circleImpl: circle,
    saveImpl: async (u, body) => {
      bodies.push(body);
      const first = bodies.length === 1;
      return {
        status: 201,
        payload: { place: { id: `p${bodies.length}` }, piggyBank: first ? { credited: true, coins: 25 } : { credited: false } },
        afterResponse: async () => { after += 1; }
      };
    }
  });
  expect(bodies.map((b) => b.name)).toEqual(['A', 'B', 'C']);
  expect(out.saved).toEqual([{ placeId: 'p1', name: 'A' }, { placeId: 'p2', name: 'B' }, { placeId: 'p3', name: 'C' }]);
  expect(out.coins).toBe(25);
  expect(out.circleId).toBe('fav1');
  await new Promise((resolve) => setImmediate(resolve));
  expect(after).toBe(3);
});

test('a duplicate is reported as already saved, a refusal as failed, and the rest still save', async () => {
  const answers = [
    { status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'old1' } },
    { status: 403, payload: { upgradeRequired: true, message: 'limit' } },
    { status: 201, payload: { place: { id: 'p3' } } }
  ];
  const out = await saveFavoritesForClip(user, [pick('A'), pick('B'), pick('C')], {
    circleImpl: circle,
    saveImpl: async () => answers.shift()
  });
  expect(out.alreadySaved).toEqual([{ placeId: 'old1', name: 'A' }]);
  expect(out.failed).toEqual([{ name: 'B', reason: '403' }]);
  expect(out.saved).toEqual([{ placeId: 'p3', name: 'C' }]);
});

test('a save that throws fails that pick only', async () => {
  const out = await saveFavoritesForClip(user, [pick('A'), pick('B')], {
    circleImpl: circle,
    saveImpl: async (u, body) => { if (body.name === 'A') throw new Error('boom'); return { status: 201, payload: { place: { id: 'p2' } } }; }
  });
  expect(out.failed).toEqual([{ name: 'A', reason: 'error' }]);
  expect(out.saved).toEqual([{ placeId: 'p2', name: 'B' }]);
});

test('no starter circle yet: every pick fails as no_circle, nothing saved', async () => {
  const save = jest.fn();
  const out = await saveFavoritesForClip(user, [pick('A')], { circleImpl: async () => null, saveImpl: save });
  expect(out.failed).toEqual([{ name: 'A', reason: 'no_circle' }]);
  expect(save).not.toHaveBeenCalled();
});

test('nothing valid: nothing asked of the circle or the save', async () => {
  const circleImpl = jest.fn();
  const out = await saveFavoritesForClip(user, [{ name: '' }, 'junk'], { circleImpl, saveImpl: jest.fn() });
  expect(out).toEqual({ saved: [], alreadySaved: [], failed: [], coins: 0, circleId: null });
  expect(circleImpl).not.toHaveBeenCalled();
});

test('the summary is cleaned and merged onto the user', async () => {
  const writes = [];
  const db = { collection: () => ({ doc: (id) => ({ set: async (data, opts) => { writes.push({ id, data, opts }); } }) }) };
  const clean = await recordClipOnboarding('u1', {
    zipcodeSet: 'yes', favoritesSaved: 2.6, followed: 99, skipped: ['people', 'bogus'], code: '3OZM82'
  }, { db });
  expect(writes).toHaveLength(1);
  expect(writes[0].id).toBe('u1');
  expect(writes[0].opts).toEqual({ merge: true });
  expect(clean).toMatchObject({ zipcodeSet: false, favoritesSaved: 3, followed: 50, skipped: ['people'], code: '3OZM82' });
  expect(typeof clean.completedAt).toBe('string');
});
