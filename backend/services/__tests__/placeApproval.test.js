// A place no map source knows waits for the admin, its saves private; approve
// gives the saves their privacy back (Wes, 2026-11-05).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('firebase-admin', () => ({ firestore: { FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue } }));

const approval = require('../placeApproval');

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
});

test('needsApproval: only saves no Google listing or Apple place backs', () => {
  expect(approval.needsApproval({ name: "Dad's House" })).toBe(true);
  expect(approval.needsApproval({ googlePlaceId: 'ChIJaddr', googleTypes: ['premise', 'street_address'] })).toBe(true);
  expect(approval.needsApproval({ googlePlaceId: 'ChIJbar', googleTypes: ['bar', 'establishment'] })).toBe(false);
  expect(approval.needsApproval({ applePoiCategory: 'MKPOICategoryCafe' })).toBe(false);
  expect(approval.needsApproval({ applePlaceId: 'I123' })).toBe(false);
  // An Apple Maps POI pick with no category and no identifier (older iOS) still counts
  expect(approval.needsApproval({ appleMatched: true })).toBe(false);
  expect(approval.needsApproval({ appleMatched: 'yes' })).toBe(true);
});

test('a minted unknown place waits, its save turns private, the admin is told; approve restores', async () => {
  mockDb.collection('globalPlaces').doc('v1').set({ name: "Dad's House", address: '1 Main St' });
  mockDb.collection('places').doc('s1').set({ name: "Dad's House", privacy: 'public', addedBy: 'u1', globalPlaceId: 'v1' });
  const alertAdmin = jest.fn();
  const saveDoc = await mockDb.collection('places').doc('s1').get();
  expect(await approval.onSaveLinked({ saveDoc, venueId: 'v1', venue: {}, minted: true }, { alertAdmin })).toBe('pending');
  expect((await mockDb.collection('globalPlaces').doc('v1').get()).data().approvalStatus).toBe('pending');
  expect((await mockDb.collection('places').doc('s1').get()).data()).toMatchObject({ privacy: 'private', privacyBeforeApproval: 'public' });
  expect(alertAdmin).toHaveBeenCalledTimes(1);
  expect(approval.isHiddenVenue((await mockDb.collection('globalPlaces').doc('v1').get()).data())).toBe(true);

  const pending = await approval.listPending();
  expect(pending.map((p) => p.id)).toEqual(['v1']);

  await approval.decide('v1', 'approved', 'admin');
  const save = (await mockDb.collection('places').doc('s1').get()).data();
  expect(save.privacy).toBe('public');
  expect(save.privacyBeforeApproval).toBeUndefined();
  await expect(approval.decide('v1', 'approved', 'admin')).rejects.toMatchObject({ status: 409 });
});

test('a known business is never held; a second save of a waiting place is held private', async () => {
  mockDb.collection('places').doc('s2').set({ name: 'Cafe', privacy: 'public', applePoiCategory: 'MKPOICategoryCafe' });
  const biz = await mockDb.collection('places').doc('s2').get();
  expect(await approval.onSaveLinked({ saveDoc: biz, venueId: 'v2', venue: {}, minted: true }, { alertAdmin: jest.fn() })).toBeNull();

  mockDb.collection('places').doc('s3').set({ name: "Dad's House", privacy: 'connections' });
  const second = await mockDb.collection('places').doc('s3').get();
  expect(await approval.onSaveLinked({ saveDoc: second, venueId: 'v1', venue: { approvalStatus: 'pending' }, minted: false })).toBe('held');
  expect((await mockDb.collection('places').doc('s3').get()).data()).toMatchObject({ privacy: 'private', privacyBeforeApproval: 'connections' });
});
