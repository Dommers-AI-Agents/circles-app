// enrichSaveFromGoogle called a function through require('../checkInController'),
// a path that doesn't exist from services/, so every share-extension, Build my
// map and dog-spot save that asked for Google's details stayed bare (2026-10-23).
// Runs the real module with only Google and Firestore faked.
jest.mock('../../config/config', () => ({ googleMapsApiKey: 'test-key' }));
jest.mock('@googlemaps/google-maps-services-js', () => ({
  Client: class {
    async findPlaceFromText() {
      return { data: { candidates: [{ place_id: 'ChIJreal', name: 'Skiptown Charlotte' }] } };
    }
    async placeDetails() {
      return { data: { result: {
        name: 'Skiptown Charlotte', formatted_address: '222 Rampart St, Charlotte, NC 28203, USA',
        rating: 4.6, user_ratings_total: 1101, formatted_phone_number: '(980) 555-0100', types: ['park']
      } } };
    }
  }
}));
jest.mock('../globalPlaceResolver', () => ({ findCanonicalByNameAndLocation: async () => null }));
jest.mock('../storage', () => ({ downloadAndUploadMultipleImages: async () => ({ uploadedUrls: [] }) }));

const { enrichSaveFromGoogle } = require('../googleEnrichment');

it('fills a bare save with Google\'s details', async () => {
  const save = { name: 'Skiptown', address: '222 Rampart St Charlotte', location: { type: 'Point', coordinates: [-80.8645747, 35.2088955] } };
  expect(await enrichSaveFromGoogle(save)).toBe(true);
  expect(save).toMatchObject({
    googlePlaceId: 'ChIJreal', name: 'Skiptown Charlotte', address: '222 Rampart St, Charlotte, NC 28203, USA',
    rating: 4.6, userRatingsTotal: 1101, phone: '(980) 555-0100'
  });
});
