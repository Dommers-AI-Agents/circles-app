// Dog spots (2026-10-23): a spot picked in Can I Pet Dat Dog goes through the
// core save (the one behind Add Place), so it gets Google's details and the
// any-circle duplicate check. Wes's Skiptown had come out a bare record.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
const mockCalls = [];
let mockNext = null;
jest.mock('../placeSaveService', () => ({
  savePlace: async (user, body) => { mockCalls.push({ user, body }); return mockNext(body); }
}));

const places = require('../dogPark/places');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const WES = { uid: 'wes' };
const SKIPTOWN = { name: 'Skiptown', address: '222 Rampart St, Charlotte, NC, 28203', lat: 35.2088955, lng: -80.8645747, category: 'retail' };

beforeEach(async () => {
  mockCalls.length = 0;
  mockDb.rows(COLLECTIONS.CIRCLES).clear();
  await mockDb.collection(COLLECTIONS.USERS).doc('wes').set({ displayName: 'Wes' });
});

it('saves through the core save into Dog spots, asking for Google details', async () => {
  const after = jest.fn();
  mockNext = (body) => ({ status: 201, payload: { place: { id: 'p1' } }, afterResponse: after });
  const out = await places.savePlace(WES, SKIPTOWN);
  expect(out).toMatchObject({ placeId: 'p1', circleName: 'Dog spots', alreadySaved: false, afterResponse: after });
  const { user, body } = mockCalls[0];
  expect(user).toBe(WES);
  expect(body).toMatchObject({
    circleId: out.circleId, name: 'Skiptown', address: SKIPTOWN.address, category: 'retail', enrichFromGoogle: true,
    location: { type: 'Point', coordinates: [SKIPTOWN.lng, SKIPTOWN.lat] }
  });
  const circle = (await mockDb.collection(COLLECTIONS.CIRCLES).doc(out.circleId).get()).data();
  expect(circle).toMatchObject({ name: 'Dog spots', owner: 'wes', isDogSpotsCircle: true });
});

it('already saved in another circle: hands back that save, makes no second one', async () => {
  mockNext = () => ({ status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'old', existingCircleId: 'charlotte', existingCircleName: 'Charlotte' } });
  expect(await places.savePlace(WES, SKIPTOWN)).toEqual({ placeId: 'old', circleId: 'charlotte', circleName: 'Charlotte', alreadySaved: true });
});

it('already in Dog spots: says so', async () => {
  mockNext = (body) => ({ status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'p1', existingCircleId: body.circleId } });
  expect(await places.savePlace(WES, SKIPTOWN)).toMatchObject({ placeId: 'p1', circleName: 'Dog spots', alreadySaved: true });
});

it('passes the core save\'s refusal on (the free plan\'s place limit)', async () => {
  mockNext = () => ({ status: 403, payload: { message: 'You have reached your limit', upgradeRequired: true } });
  await expect(places.savePlace(WES, SKIPTOWN)).rejects.toMatchObject({ status: 403, code: 'upgrade_required' });
});

it('a spot with no street address still saves (Google fills it in)', async () => {
  mockNext = () => ({ status: 201, payload: { place: { id: 'p2' } } });
  await places.savePlace(WES, { ...SKIPTOWN, address: '' });
  expect(mockCalls[0].body.address).toBe('35.20890, -80.86457');
});
