// The App Clip's window scan saves the store (2026-11-01)
const mockOwnSave = { doc: null };
jest.mock('../ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => mockOwnSave.doc }));
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { saveStoreForClip, saveBodyFor } = require('../clipStoreSave');

const venue = {
  venueId: 'v1', venueName: 'Sal’s Bakery (Demo)', placeName: 'Sal’s Bakery (Demo)', placeAddress: '1 Main St, Charlotte, NC',
  category: 'bakery', googlePlaceId: 'g1', globalPlaceId: 'gp1', location: { lat: 35.2, lng: -80.8 }
};
const user = { uid: 'u1' };
const circle = async () => ({ id: 'fav1' });

beforeEach(() => { mockOwnSave.doc = null; });

test('saves the store to Favorite Local Spots through the core save', async () => {
  const calls = [];
  const out = await saveStoreForClip(user, venue, {
    circleImpl: circle,
    saveImpl: async (u, body) => { calls.push(body); return { status: 201, payload: { place: { id: 'p1' } } }; }
  });
  expect(out).toEqual({ saved: true, alreadySaved: false, savedPlace: { placeId: 'p1', circleId: 'fav1' } });
  expect(calls[0]).toMatchObject({ circleId: 'fav1', name: 'Sal’s Bakery (Demo)', googlePlaceId: 'g1',
    location: { type: 'Point', coordinates: [-80.8, 35.2] } });
});

test('already saved anywhere: no second save', async () => {
  mockOwnSave.doc = { id: 'p0', data: () => ({ circleId: 'c9' }) };
  const save = jest.fn();
  const out = await saveStoreForClip(user, venue, { circleImpl: circle, saveImpl: save });
  expect(out).toEqual({ saved: false, alreadySaved: true, savedPlace: { placeId: 'p0', circleId: 'c9' } });
  expect(save).not.toHaveBeenCalled();
});

test('the core save calls it a duplicate: reported as already saved', async () => {
  const out = await saveStoreForClip(user, venue, {
    circleImpl: circle,
    saveImpl: async () => ({ status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'p2', existingCircleId: 'c2' } })
  });
  expect(out.alreadySaved).toBe(true);
  expect(out.savedPlace).toEqual({ placeId: 'p2', circleId: 'c2' });
});

test('no starter circle yet, or a refused save: pending for the app to finish', async () => {
  expect((await saveStoreForClip(user, venue, { circleImpl: async () => null })).pending).toBe(true);
  const out = await saveStoreForClip(user, venue, { circleImpl: circle, saveImpl: async () => ({ status: 403, payload: { upgradeRequired: true } }) });
  expect(out).toMatchObject({ saved: false, pending: true });
});

test('an online-only brand is never put on a map', async () => {
  expect((await saveStoreForClip(user, { ...venue, isVirtual: true })).pending).toBe(true);
});

test('a store with no address still gets one from its spot', () => {
  expect(saveBodyFor({ ...venue, placeAddress: null }, 'c').address).toBe('35.20000, -80.80000');
});
