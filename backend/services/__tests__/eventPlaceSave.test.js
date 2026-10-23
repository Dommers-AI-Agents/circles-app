// Event places save through the core save (2026-10-23): Matti's Condado
// Tacos, saved from an event, came out with no photo or Google details
// because the event save wrote a bare record.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));
jest.mock('../notificationService', () => ({}));
const mockCalls = [];
let mockNext = null;
jest.mock('../placeSaveService', () => ({
  savePlace: async (user, body) => { mockCalls.push({ user, body }); return mockNext(body); }
}));

const events = require('../eventService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const MATTI = { uid: 'matti', displayName: 'Matti' };
const TACOS = { name: 'Condado Tacos', address: '1536 Camden Rd, Charlotte, NC, 28203', lat: 35.2125, lng: -80.8598, category: 'restaurant' };

async function eventWithPlace() {
  await mockDb.collection(COLLECTIONS.USERS).doc('matti').set({ displayName: 'Matti' });
  const ev = await events.eventsCol().add({ name: 'Party Bus', ownerId: 'matti', memberIds: ['matti'], members: ['matti'], createdAt: new Date().toISOString(), deletedAt: null });
  const pl = await events.placesCol().add({ eventId: ev.id, ...TACOS, savedBy: [], addedBy: 'matti' });
  return { eventId: ev.id, placeId: pl.id };
}

beforeEach(() => { mockCalls.length = 0; });

it('asks the core save for Google details, then follows up after the reply', async () => {
  const { eventId, placeId } = await eventWithPlace();
  const after = jest.fn();
  mockNext = () => ({ status: 201, payload: { place: { id: 'p1' } }, afterResponse: after });
  const out = await events.savePlaceToMyCircle(eventId, MATTI, placeId);
  expect(out).toMatchObject({ alreadySaved: false, afterResponse: after });
  const { user, body } = mockCalls[0];
  expect(user).toBe(MATTI);
  expect(body).toMatchObject({
    circleId: out.circleId, name: 'Condado Tacos', address: TACOS.address, category: 'restaurant', enrichFromGoogle: true,
    location: { type: 'Point', coordinates: [TACOS.lng, TACOS.lat] }
  });
  // The event's place now shows Matti saved it
  expect(out.place).toMatchObject({ name: 'Condado Tacos', savedByMe: true });
});

it('already saved in any circle: that save stands, nothing new', async () => {
  const { eventId, placeId } = await eventWithPlace();
  mockNext = () => ({ status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'old', existingCircleId: 'favs' } });
  const out = await events.savePlaceToMyCircle(eventId, MATTI, placeId);
  expect(out).toMatchObject({ alreadySaved: true, circleId: 'favs' });
  expect(out.afterResponse).toBeUndefined();
});

it('a refused save (place limit) is an error, not a silent success', async () => {
  const { eventId, placeId } = await eventWithPlace();
  mockNext = () => ({ status: 403, payload: { upgradeRequired: true, message: 'Upgrade to save more places' } });
  await expect(events.savePlaceToMyCircle(eventId, MATTI, placeId)).rejects.toMatchObject({ status: 403, code: 'upgrade_required' });
});
