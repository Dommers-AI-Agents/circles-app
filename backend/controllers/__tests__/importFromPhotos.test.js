const mockSet = jest.fn(() => Promise.resolve());
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: () => ({ doc: () => ({ set: mockSet }) }) })
}));
jest.mock('../../services/importService', () => ({ executeImport: jest.fn() }));
jest.mock('../../services/subscriptionLimitService', () => ({ photoPlacesAllowance: jest.fn(), canImport: jest.fn(async () => ({ canImport: true })) }));
jest.mock('../../services/swarmService', () => ({}));
jest.mock('../../services/piggyBankService', () => ({ credit: jest.fn(async () => ({ credited: true, coins: 3 })) }));
jest.mock('../../services/googleListResolver', () => ({ resolveGoogleList: jest.fn(), GoogleListError: class {} }));

const importService = require('../../services/importService');
const limits = require('../../services/subscriptionLimitService');
const controller = require('../importController');
const piggyBank = require('../../services/piggyBankService');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const places = (n) => Array.from({ length: n }, (_, i) => ({ name: `Spot ${i}`, lat: 35 + i / 1000, lng: -80, photos: ['https://x/p.jpg'] }));
const run = async (body) => {
  const r = res();
  await controller.importFromPhotos({ user: { uid: 'u1' }, body }, r);
  return r;
};

beforeEach(() => {
  jest.clearAllMocks();
  importService.executeImport.mockImplementation(async (uid, payload) => ({
    results: [{ circleId: 'c1', created: payload.lists[0].places.length, skippedDuplicates: 0, failed: [] }]
  }));
});

test('free users: the batch is cut to what is left of the 25, and told to upgrade', async () => {
  limits.photoPlacesAllowance.mockResolvedValue({ remaining: 5, max: 25, used: 20 });
  const r = await run({ places: places(10) });
  const payload = importService.executeImport.mock.calls[0][1];
  expect(payload.source).toBe('photos');
  expect(payload.lists[0].name).toBe('Places from my photos');
  expect(payload.lists[0].places).toHaveLength(5);
  expect(r.json.mock.calls[0][0].data).toMatchObject({ added: 5, remainingFree: 0, maxFree: 25, upgradeRequired: true, circleId: 'c1' });
  expect(mockSet).toHaveBeenCalledWith({ photoMapBuiltAt: expect.any(String) }, { merge: true });
});

test('FavCoins: one 3-coin earn for the import, not one per place', async () => {
  limits.photoPlacesAllowance.mockResolvedValue({ remaining: 25, max: 25, used: 0 });
  const r = await run({ places: places(10) });
  expect(piggyBank.credit).toHaveBeenCalledTimes(1);
  expect(piggyBank.credit).toHaveBeenCalledWith({ userId: 'u1', eventType: 'photo_map_built', sourceRef: { circleId: 'c1' } });
  expect(r.json.mock.calls[0][0].data.coins).toBe(3);

  // Nothing added: nothing earned
  importService.executeImport.mockResolvedValueOnce({ results: [{ circleId: 'c1', created: 0, skippedDuplicates: 2, failed: [] }] });
  piggyBank.credit.mockClear();
  await run({ places: places(2) });
  expect(piggyBank.credit).not.toHaveBeenCalled();
});

test('allowance used up: 403 upgradeRequired, nothing added', async () => {
  limits.photoPlacesAllowance.mockResolvedValue({ remaining: 0, max: 25, used: 25 });
  const r = await run({ places: places(3) });
  expect(r.status).toHaveBeenCalledWith(403);
  expect(r.json.mock.calls[0][0]).toMatchObject({ upgradeRequired: true });
  expect(importService.executeImport).not.toHaveBeenCalled();
});

test('Premium: everything in the batch, no remaining count', async () => {
  limits.photoPlacesAllowance.mockResolvedValue({ remaining: Infinity, max: Infinity, used: 0 });
  const r = await run({ places: places(25) });
  expect(importService.executeImport.mock.calls[0][1].lists[0].places).toHaveLength(25);
  expect(r.json.mock.calls[0][0].data).toMatchObject({ added: 25, remainingFree: null, upgradeRequired: false });
});

test('bad requests: empty, or more than 25 at once', async () => {
  expect((await run({ places: [] })).status).toHaveBeenCalledWith(400);
  expect((await run({ places: places(26) })).status).toHaveBeenCalledWith(400);
});

test('the general import endpoint refuses the photos source (it would skip the allowance)', async () => {
  const r = res();
  await controller.executeImport({ user: { uid: 'u1' }, body: { source: 'photos', lists: [] } }, r);
  expect(r.status).toHaveBeenCalledWith(400);
  expect(importService.executeImport).not.toHaveBeenCalled();
});

test('the earn is keyed once per person', () => {
  const { derivePiggyDedupKey } = jest.requireActual('../../models/PiggyBankModels');
  const config = jest.requireActual('../../config/piggyBankConfig');
  expect(derivePiggyDedupKey('photo_map_built', { userId: 'u1', circleId: 'c1' })).toBe('photo_map:u1');
  expect(derivePiggyDedupKey('photo_map_built', { userId: 'u1', circleId: 'c2' })).toBe('photo_map:u1');
  expect(config.COINS.PHOTO_MAP_BUILT).toBe(3);
});
