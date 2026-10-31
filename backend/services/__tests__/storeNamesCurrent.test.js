// A store's name comes from its record as it is NOW: the points history and
// a newly approved claim no longer carry a copy from an earlier day
// (Wes, 2026-10-31: one name, everywhere).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../emailService', () => ({
  sendStickerQREmail: jest.fn(async () => {}),
  sendClaimApprovedEmail: jest.fn(async () => {})
}));
jest.mock('../notificationService', () => ({ notifyStoreClaimApproved: jest.fn(async () => {}) }));

const rewardService = require('../rewardService');
const emailService = require('../emailService');
const notificationService = require('../notificationService');
const { updateVenueDetails } = require('../venueDetailsService');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const respond = () => ({ statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } });

beforeEach(async () => {
  for (const name of ['globalPlaces', 'places', 'stickerVenues', 'users', 'rewardEvents', 'venueClaimRequests']) mockDb.rows(name).clear();
  jest.clearAllMocks();
  await put('globalPlaces', 'g1', { name: 'Test Bakery', address: '1 Main St', category: 'cafe',
    location: { type: 'Point', coordinates: [-80.86, 35.21] } });
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Test Bakery', placeName: 'Test Bakery', ownerUserId: 'owner' });
});

test('GET /rewards/balance: balances AND history rows name the store as it is called now', async () => {
  await put('users', 'cust', { rewardPoints: 60, rewardPointsByVenue: { v1: { points: 50, venueName: 'Test Bakery' } } });
  await put('rewardEvents', 'e1', { userId: 'cust', venueId: 'v1', venueName: 'Test Bakery', points: 50, createdAt: '2026-10-01' });
  await put('rewardEvents', 'e2', { userId: 'cust', venueId: 'vGone', venueName: 'Old Shop', points: 5, createdAt: '2026-10-02' });
  await put('rewardEvents', 'e3', { userId: 'cust', type: 'signup_bonus', points: 5, createdAt: '2026-10-03' });
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'owner' }, fields: { name: "Sal's Bakery" } });

  const { venueBalances, events } = await rewardService.getBalance('cust');
  expect(venueBalances).toEqual([{ venueId: 'v1', venueName: "Sal's Bakery", points: 50 }]);
  const byId = Object.fromEntries(events.map((e) => [e.id, e]));
  expect(byId.e1.venueName).toBe("Sal's Bakery");
  expect(byId.e2.venueName).toBe('Old Shop');
  expect(byId.e3.venueName).toBeUndefined();

  const lean = await rewardService.getBalance('cust', { withEvents: false });
  expect(lean.venueBalances[0].venueName).toBe("Sal's Bakery");
});

test("approving a claim on a new store names it from the place as it is now, not the claim's copy", async () => {
  await mockDb.collection('stickerVenues').doc('v1').delete();
  await updateVenueDetails({ globalPlaceId: 'g1', user: { uid: 'admin', isSuperUser: true },
    fields: { name: "Sal's Bakery", address: '2 Main St, Charlotte, NC 28203' } });
  await put('venueClaimRequests', 'c1', { status: 'pending', userId: 'claimant', globalPlaceId: 'g1',
    placeName: 'Test Bakery', placeAddress: '1 Main St', userEmail: 'sal@example.com' });
  const createVenue = jest.spyOn(rewardService, 'createVenue').mockImplementation(async (data) => ({ venueId: 'vNew', ...data }));
  jest.spyOn(rewardService, 'assignVenueOwner').mockImplementation(async () => {});

  const { approveClaim } = require('../../controllers/venues/venueClaimsController');
  const res = respond();
  await approveClaim({ params: { claimId: 'c1' }, user: { uid: 'admin' } }, res);

  expect(res.body.success).toBe(true);
  expect(createVenue.mock.calls[0][0]).toMatchObject({ venueName: "Sal's Bakery", placeName: "Sal's Bakery",
    placeAddress: '2 Main St, Charlotte, NC 28203', globalPlaceId: 'g1', category: 'cafe' });
  expect(notificationService.notifyStoreClaimApproved.mock.calls[0][0]).toMatchObject({ venueName: "Sal's Bakery" });
  expect(emailService.sendClaimApprovedEmail.mock.calls[0][2]).toBe("Sal's Bakery");
});
