// Check-in reach and spend (security audit 2026-10-01): recipients limited
// to the person's own conversations and accepted connections; paid Google
// lookups need a location, a daily allowance, and skip remembered misses.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const guards = require('../checkInGuards');

const reset = () => {
  for (const name of [COLLECTIONS.CONVERSATIONS, COLLECTIONS.CONNECTIONS, 'placesLookupMisses', 'dailyBudgets']) {
    mockDb.rows(name).clear();
  }
  delete process.env.PLACES_LOOKUP_DAILY_BUDGET;
};
beforeEach(reset);

describe('sanitizeCheckInRecipients', () => {
  beforeEach(async () => {
    await mockDb.collection(COLLECTIONS.CONVERSATIONS).doc('mine').set({ type: 'group', participants: ['wes', 'britt'] });
    await mockDb.collection(COLLECTIONS.CONVERSATIONS).doc('theirs').set({ type: 'group', participants: ['sal', 'joe'] });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c1').set({ userId: 'wes', connectedUserId: 'britt', status: 'accepted' });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c2').set({ userId: 'joe', connectedUserId: 'wes', status: 'accepted' });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c3').set({ userId: 'wes', connectedUserId: 'sal', status: 'pending' });
    await mockDb.collection(COLLECTIONS.CONNECTIONS).doc('c4').set({ userId: 'wes', connectedUserId: 'blocky', status: 'accepted' });
  });

  test('keeps only own conversations and accepted, unblocked connections', async () => {
    const out = await guards.sanitizeCheckInRecipients('wes', { blockedUsers: ['blocky'] }, {
      notifiedGroups: ['mine', 'theirs', 'missing', 'mine'],
      notifiedUsers: ['britt', 'joe', 'sal', 'stranger', 'blocky', 'wes']
    });
    expect(out.notifiedGroups).toEqual(['mine']);
    expect(out.notifiedUsers.sort()).toEqual(['britt', 'joe']);
  });

  test('garbage and oversize lists are trimmed, not trusted', async () => {
    const many = Array.from({ length: 80 }, (_, i) => `u${i}`);
    const out = await guards.sanitizeCheckInRecipients('wes', {}, { notifiedGroups: 'mine', notifiedUsers: [null, 3, ...many] });
    expect(out).toEqual({ notifiedGroups: [], notifiedUsers: [] });
  });
});

test('capPlaceText bounds venue text that ends up in pushes', () => {
  const data = guards.capPlaceText({ placeName: 'x'.repeat(5000), placeAddress: 'y'.repeat(5000) });
  expect(data.placeName).toHaveLength(guards.MAX_PLACE_NAME);
  expect(data.placeAddress.length).toBeLessThanOrEqual(300);
});

describe('gatedPlacesLookup', () => {
  const here = { latitude: 35.2271, longitude: -80.8431 };

  test('no location, no paid lookup', async () => {
    const lookup = jest.fn();
    expect(await guards.gatedPlacesLookup({ userId: 'wes', placeName: 'Fake Cafe', location: null, lookup })).toEqual({});
    expect(lookup).not.toHaveBeenCalled();
  });

  test('a definite miss is remembered for the same name at the same spot', async () => {
    const lookup = jest.fn(async () => ({ noMatch: true }));
    await guards.gatedPlacesLookup({ userId: 'wes', placeName: 'Fake Cafe 123', location: here, lookup });
    await guards.gatedPlacesLookup({ userId: 'sal', placeName: '  fake   CAFE 123 ', location: { latitude: 35.22712, longitude: -80.84309 }, lookup });
    expect(lookup).toHaveBeenCalledTimes(1);
    // A different spot is a different question
    await guards.gatedPlacesLookup({ userId: 'wes', placeName: 'Fake Cafe 123', location: { latitude: 40.7, longitude: -74 }, lookup });
    expect(lookup).toHaveBeenCalledTimes(2);
  });

  test('an error result is not cached as a miss', async () => {
    const lookup = jest.fn(async () => ({}));
    await guards.gatedPlacesLookup({ userId: 'wes', placeName: 'Real Place', location: here, lookup });
    await guards.gatedPlacesLookup({ userId: 'wes', placeName: 'Real Place', location: here, lookup });
    expect(lookup).toHaveBeenCalledTimes(2);
  });

  test('the per-user daily cap stops paid lookups', async () => {
    process.env.PLACES_LOOKUP_DAILY_BUDGET = '2';
    const lookup = jest.fn(async (name) => ({ googlePlaceId: `g-${name}` }));
    for (const name of ['a', 'b', 'c']) {
      await guards.gatedPlacesLookup({ userId: 'wes', placeName: name, location: here, lookup });
    }
    expect(lookup).toHaveBeenCalledTimes(2);
    expect(await guards.gatedPlacesLookup({ userId: 'britt', placeName: 'c', location: here, lookup })).toEqual({ googlePlaceId: 'g-c' });
  });
});
