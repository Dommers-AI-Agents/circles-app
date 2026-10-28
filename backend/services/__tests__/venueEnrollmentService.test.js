// Super-user "print this store's QR codes" (2026-10-28): any place on the map
// gets a venue record on demand, once, with no owner attached.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../rewardService', () => ({
  createVenue: jest.fn(async (data) => ({ venueId: 'v_new', windowCode: 'WIN123', registerCode: 'REG123', ...data }))
}));

const rewardService = require('../rewardService');
const svc = require('../venueEnrollmentService');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');

const GLOBAL = {
  name: 'Tommys Tavern', address: '1 Main St, Charlotte, NC', googlePlaceId: 'g_tommys',
  location: { type: 'Point', coordinates: [-80.84, 35.22] }, category: 'bar'
};

beforeEach(async () => {
  rewardService.createVenue.mockClear();
  mockDb.rows('globalPlaces').clear();
  mockDb.rows(COLLECTIONS.PLACES).clear();
  mockDb.rows(STICKER_COLLECTIONS.STICKER_VENUES).clear();
  await mockDb.collection('globalPlaces').doc('gp1').set(GLOBAL);
  await mockDb.collection(COLLECTIONS.PLACES).doc('save1').set({ name: 'Tommys (my save)', address: 'cached', globalPlaceId: 'gp1', addedBy: 'wes' });
  await mockDb.collection(COLLECTIONS.PLACES).doc('legacy1').set({ name: 'Old Deli', address: '9 Side St', googlePlaceId: 'g_deli', location: { coordinates: [-80.1, 35.1] }, category: 'restaurant' });
});

it('reads the venue fields off the canonical place, GeoJSON turned into lat/lng', async () => {
  const fields = await svc.placeVenueFields('gp1');
  expect(fields).toEqual({
    venueName: 'Tommys Tavern', placeName: 'Tommys Tavern', placeAddress: '1 Main St, Charlotte, NC',
    googlePlaceId: 'g_tommys', globalPlaceId: 'gp1', location: { lat: 35.22, lng: -80.84 }, category: 'bar'
  });
});

it('follows a save to its canonical place, and reads a legacy save on its own', async () => {
  const viaSave = await svc.placeVenueFields('save1');
  expect(viaSave.venueName).toBe('Tommys Tavern');
  expect(viaSave.globalPlaceId).toBe('gp1');
  const legacy = await svc.placeVenueFields('legacy1');
  expect(legacy).toMatchObject({ venueName: 'Old Deli', googlePlaceId: 'g_deli', globalPlaceId: null, location: { lat: 35.1, lng: -80.1 } });
  expect(await svc.placeVenueFields('nope')).toBeNull();
});

it('mints a venue with no owner or contact, and never twice for one store', async () => {
  const first = await svc.enrollPlace('save1');
  expect(first.created).toBe(true);
  expect(rewardService.createVenue).toHaveBeenCalledWith(expect.objectContaining({
    venueName: 'Tommys Tavern', globalPlaceId: 'gp1', googlePlaceId: 'g_tommys', category: 'bar'
  }));
  const sent = rewardService.createVenue.mock.calls[0][0];
  expect(sent.contactEmail).toBeUndefined();
  expect(sent.ownerUserId).toBeUndefined();

  // The real store already has its codes (even if it was deactivated)
  await mockDb.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc('v_old').set({ venueName: 'Tommys Tavern', globalPlaceId: 'gp1', windowCode: 'OLD1', registerCode: 'OLD2', active: false });
  const again = await svc.enrollPlace('gp1');
  expect(again).toMatchObject({ created: false, venue: { venueId: 'v_old', windowCode: 'OLD1' } });
  expect(rewardService.createVenue).toHaveBeenCalledTimes(1);
});

it('refuses a place that no longer exists', async () => {
  await expect(svc.enrollPlace('gone')).rejects.toMatchObject({ status: 404, code: 'PLACE_NOT_FOUND' });
});
