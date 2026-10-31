jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../zipcodeService', () => ({
  geocodeZipcode: jest.fn(async (zip) => (zip === '28203' ? { city: 'Charlotte', state: 'NC' } : {}))
}));
const rewardService = require('../rewardService');

describe('a new clip account starts where it joined', () => {
  test('store coordinates, ZIP and city', async () => {
    const home = await rewardService.homeFromStore({
      location: { lat: 35.21, lng: -80.86 },
      placeAddress: '1500 East Blvd, Charlotte, NC 28203-5678, United States'
    });
    expect(home.lastKnownLocation).toMatchObject({ latitude: 35.21, longitude: -80.86, source: 'store_scan' });
    expect(home.zipcode).toBe('28203');
    expect(home.location).toBe('Charlotte, NC');
  });

  test('a street number is not a ZIP; the last 5-digit run is', async () => {
    const home = await rewardService.homeFromStore({ placeAddress: '12345 Main St, Charlotte, NC 28203' });
    expect(home.zipcode).toBe('28203');
  });

  test('nothing for the generic code, an online brand, or no data', async () => {
    expect(await rewardService.homeFromStore({ genericJoin: true, location: { lat: 1, lng: 1 } })).toEqual({});
    expect(await rewardService.homeFromStore({ isVirtual: true, location: { lat: 1, lng: 1 } })).toEqual({});
    expect(await rewardService.homeFromStore({})).toEqual({});
  });
});
