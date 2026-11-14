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

// Wes, 2026-11-14: RA Sushi Bar, saved from Apple Maps without a Google id,
// never got rating, hours or a photo — only share-extension saves looked.
describe('a save without a Google id from the app', () => {
  const { isSameVenueListing, isGeneratedDescription } = require('../googleEnrichment');
  const at = { latitude: 32.3254, longitude: -110.9289 };
  const listing = (name, lat = 32.3256, lng = -110.9290) => ({ name, geometry: { location: { lat, lng } } });

  it('takes Google\'s listing of that name nearby', () => {
    expect(isSameVenueListing('RA Sushi Bar Restaurant', at, listing('RA Sushi Bar Restaurant'))).toBe(true);
    expect(isSameVenueListing('Starbucks', at, listing('Starbucks Coffee'))).toBe(true);
    expect(isSameVenueListing('Little Caesars', at, listing('Little Caesars Pizza'))).toBe(true);
    // Google's own wording, right on the pin
    expect(isSameVenueListing('RA Sushi Bar Restaurant', at, listing('RA Sushi - Tucson', 32.32541, -110.92891))).toBe(true);
  });

  it('never the nearest business to a name that isn\'t one', () => {
    expect(isSameVenueListing("Mom's house", at, listing('Sushi Garden'))).toBe(false);
    expect(isSameVenueListing('Pizza Palace', at, listing('Pizza Hut'))).toBe(false);
    expect(isSameVenueListing('Pizza Palace', at, listing('Pizza Hut', 32.32541, -110.92891))).toBe(false);
    expect(isSameVenueListing("Mom's house", at, listing('Sushi Garden', 32.32541, -110.92891))).toBe(false);
    // One shared word is not enough 200 m away
    expect(isSameVenueListing('RA Sushi Bar Restaurant', at, listing('Sushi Garden', 32.3272, -110.9289))).toBe(false);
    // Same name, other side of town
    expect(isSameVenueListing('RA Sushi Bar Restaurant', at, listing('RA Sushi Bar Restaurant', 32.25, -110.85))).toBe(false);
  });

  it('replaces only the app\'s own filler description', () => {
    expect(isGeneratedDescription('Phone: +1 (520) 448-3572\nWebsite: https://rasushi.com/')).toBe(true);
    expect(isGeneratedDescription('A dining establishment in Tucson\nPhone: 555')).toBe(true);
    expect(isGeneratedDescription('')).toBe(true);
    expect(isGeneratedDescription('Best sushi in town')).toBe(false);
    expect(isGeneratedDescription('Ask for Mike\nPhone: 555')).toBe(false);
  });
});
