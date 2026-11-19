// An older app (1.4.x) sends Google's STREET ADDRESS id for many real places.
// The save drops that id; it must then look the place itself up by name, or
// the save is left with no map match and waits in Approve places (Matti's
// Rome saves, 2026-11-18: Roman Forum, Spanish Steps, Fountain of Neptune).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../../config/config', () => ({ googleMapsApiKey: 'test-key' }));
const mockDetails = jest.fn();
jest.mock('@googlemaps/google-maps-services-js', () => ({ Client: jest.fn(() => ({ placeDetails: (...a) => mockDetails(...a) })) }));
const mockEnrich = jest.fn();
jest.mock('../googleEnrichment', () => ({ enrichSaveFromGoogle: (...a) => mockEnrich(...a) }));
jest.mock('../globalPlaceResolver', () => ({ ensureGlobalPlaceLink: jest.fn(async () => null), findCanonicalByNameAndLocation: jest.fn(async () => null) }));
jest.mock('../subscriptionLimitService', () => ({ canAddPlace: async () => ({ canAdd: true }) }));
jest.mock('../notificationService', () => ({}));
jest.mock('../activityService', () => ({ trackPlaceAdded: async () => {} }));
jest.mock('../circleCover', () => ({ ensureCircleCoverImage: async () => {} }));
jest.mock('../circleLocationSummary', () => ({ indexSavedPlace: async () => {} }));
jest.mock('../rewardService', () => ({ findVenueByPlace: async () => null }));
jest.mock('../piggyBankService', () => ({ credit: async () => null }));
jest.mock('../funnelService', () => ({ stampFunnelMilestone: () => {} }));
jest.mock('../homePromptService', () => ({}));

const { savePlace } = require('../placeSaveService');

const MATTI = { uid: 'matti', displayName: 'Matti' };
const FORUM = {
  name: 'Roman Forum', address: '5/6, Largo della Salara Vecchia, Rome, Lazio, 00186, Italy', category: 'attraction',
  googlePlaceId: 'ChIJ-address', location: { type: 'Point', coordinates: [12.48708, 41.89267] }
};

beforeEach(async () => {
  mockDetails.mockReset(); mockEnrich.mockReset();
  await mockDb.collection('circles').doc('rome').set({ owner: 'matti', sharedWith: [], name: 'Roma, Italy' });
});

it('drops an address id, then finds the place on Google by name', async () => {
  mockDetails.mockImplementation(async ({ params }) => (params.place_id === 'ChIJ-address'
    ? { data: { result: { name: 'L.go della Salara Vecchia, 5', types: ['street_address'] } } }
    : { data: { result: { name: 'Roman Forum', types: ['tourist_attraction', 'point_of_interest'] } } }));
  mockEnrich.mockImplementation(async (placeData) => { placeData.googlePlaceId = 'ChIJ-forum'; return true; });

  const out = await savePlace(MATTI, { ...FORUM, circleId: 'rome', clientSaveId: 'c1' });

  expect(mockEnrich).toHaveBeenCalledTimes(1);
  expect(mockEnrich.mock.calls[0][0]).toMatchObject({ name: 'Roman Forum' });
  expect(mockEnrich.mock.calls[0][1]).toEqual({ mustMatchName: true });
  // The found listing is checked like any Google-backed save
  expect(mockDetails.mock.calls.map((c) => c[0].params.place_id)).toEqual(['ChIJ-address', 'ChIJ-forum']);
  expect(out.status).toBe(201);
  const saved = (await mockDb.collection('places').where('clientSaveId', '==', 'c1').get()).docs[0].data();
  expect(saved.googlePlaceId).toBe('ChIJ-forum');
});

it('a real Google id is used as sent, with no extra lookup', async () => {
  mockDetails.mockResolvedValue({ data: { result: { name: 'Roman Forum', types: ['tourist_attraction'] } } });
  await savePlace(MATTI, { ...FORUM, googlePlaceId: 'ChIJ-forum', circleId: 'rome', clientSaveId: 'c2' });
  expect(mockEnrich).not.toHaveBeenCalled();
});
