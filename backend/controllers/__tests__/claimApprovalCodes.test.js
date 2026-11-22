// Every approved claim gets its store's App Clip cards published right away
// and its QR codes emailed to the approving admin, who sells the register
// code; the window code is free (Wes, 2026-11-07). Both paths: a store
// already enrolled, and one the approval enrolls.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/emailService', () => ({
  sendStickerQREmail: jest.fn(async () => {}),
  sendClaimApprovedEmail: jest.fn(async () => {})
}));
jest.mock('../../services/notificationService', () => ({ notifyStoreClaimApproved: jest.fn(async () => {}) }));
jest.mock('../../services/appClipExperienceService', () => ({ publishNewVenueQuiet: jest.fn() }));

const rewardService = require('../../services/rewardService');
const emailService = require('../../services/emailService');
const appClip = require('../../services/appClipExperienceService');
const { approveClaim } = require('../venues/venueClaimsController');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const respond = () => ({ statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } });
const admin = { uid: 'admin', email: 'wes@example.com' };

beforeEach(async () => {
  for (const name of ['globalPlaces', 'stickerVenues', 'venueClaimRequests', 'users']) mockDb.rows(name).clear();
  jest.clearAllMocks();
  jest.spyOn(rewardService, 'assignVenueOwner').mockImplementation(async () => {});
  jest.spyOn(rewardService, 'generateQRBuffers').mockImplementation(async () => ({ windowQR: 'w', registerQR: 'r' }));
  await put('globalPlaces', 'g1', { name: 'Test Bakery', address: '1 Main St', category: 'cafe',
    location: { type: 'Point', coordinates: [-80.86, 35.21] } });
});

test('a claim on an enrolled store publishes its cards and emails the codes', async () => {
  await put('stickerVenues', 'v1', { globalPlaceId: 'g1', venueName: 'Test Bakery', windowCode: 'W1', registerCode: 'R1' });
  await put('venueClaimRequests', 'c1', { status: 'pending', userId: 'claimant', venueId: 'v1', userEmail: 'sal@example.com' });

  const res = respond();
  await approveClaim({ params: { claimId: 'c1' }, user: admin }, res);

  expect(res.body.success).toBe(true);
  expect(appClip.publishNewVenueQuiet).toHaveBeenCalledWith('v1');
  expect(emailService.sendStickerQREmail).toHaveBeenCalledWith('wes@example.com',
    expect.objectContaining({ venueId: 'v1', registerCode: 'R1' }), 'w', 'r');
  expect(res.body.data.emailSent).toBe(true);
});

test('a claim that enrolls the store does the same', async () => {
  await put('venueClaimRequests', 'c1', { status: 'pending', userId: 'claimant', globalPlaceId: 'g1', userEmail: 'sal@example.com' });
  jest.spyOn(rewardService, 'createVenue').mockImplementation(async (data) => ({ venueId: 'vNew', ...data }));

  const res = respond();
  await approveClaim({ params: { claimId: 'c1' }, user: admin }, res);

  expect(res.body.success).toBe(true);
  expect(appClip.publishNewVenueQuiet).toHaveBeenCalledWith('vNew');
  expect(emailService.sendStickerQREmail).toHaveBeenCalledWith('wes@example.com', expect.objectContaining({ venueId: 'vNew' }), 'w', 'r');
});

// An owner (or their AI assistant) sees their own claims, newest first, and nobody else's
test('listMyClaims returns only the caller\'s claims, newest first', async () => {
  const { listMyClaims } = require('../venues/venueClaimsController');
  await put('venueClaimRequests', 'old', { status: 'denied', userId: 'owner1', placeName: 'Old Cafe', denialReason: 'Could not verify', createdAt: '2026-11-01T00:00:00Z' });
  await put('venueClaimRequests', 'new', { status: 'pending', userId: 'owner1', placeName: 'New Cafe', placeAddress: '2 Main St', globalPlaceId: 'g1', createdAt: '2026-11-20T00:00:00Z' });
  await put('venueClaimRequests', 'other', { status: 'pending', userId: 'someoneElse', placeName: 'Not Mine', createdAt: '2026-11-21T00:00:00Z' });

  const res = respond();
  await listMyClaims({ user: { uid: 'owner1' } }, res);

  expect(res.body.success).toBe(true);
  expect(res.body.data.claims.map((c) => c.claimId)).toEqual(['new', 'old']);
  expect(res.body.data.claims[0]).toMatchObject({ status: 'pending', businessName: 'New Cafe', address: '2 Main St' });
  expect(res.body.data.claims[1].denialReason).toBe('Could not verify');
});
