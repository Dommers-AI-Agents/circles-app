// The store's Customers list and "Remove from rewards" (2026-11-02)
const users = {};
const events = [];
const INC = (n) => ({ __inc: n });
const DEL = { __del: true };
const setPath = (obj, path, value) => {
  const keys = path.split('.');
  let o = obj;
  keys.slice(0, -1).forEach((k) => { o[k] = o[k] || {}; o = o[k]; });
  const last = keys[keys.length - 1];
  if (value && value.__inc !== undefined) o[last] = (o[last] || 0) + value.__inc;
  else if (value && value.__del) delete o[last];
  else o[last] = value;
};
const userDoc = (id) => ({
  id, ref: { update: async (u) => Object.entries(u).forEach(([k, v]) => setPath(users[id], k, v)), _id: id },
  exists: !!users[id], data: () => users[id]
});
const mockDb = {
  collection: (name) => ({
    doc: (id) => ({ _id: id, get: async () => userDoc(id), update: async (u) => Object.entries(u).forEach(([k, v]) => setPath(users[id], k, v)) }),
    where: (f1, op1, v1) => name === 'users'
      ? { limit: () => ({ get: async () => ({ docs: Object.keys(users).filter((id) => { const b = (users[id].rewardPointsByVenue || {}).v1; return b && b.points >= 0; }).map(userDoc) }) }) }
      : { where: (f2, op2, v2) => ({ get: async () => ({ forEach: (fn) => events.filter((e) => e[f1] === v1 && e[f2] === v2).forEach((e) => fn({ data: () => e })) }) }) }
  }),
  runTransaction: async (fn) => fn({
    get: async (ref) => userDoc(ref._id),
    update: (ref, u) => Object.entries(u).forEach(([k, v]) => setPath(users[ref._id], k, v))
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: { increment: (n) => INC(n), delete: () => DEL } }));
jest.mock('../../models/FirestoreModels', () => ({ COLLECTIONS: { USERS: 'users' } }));
jest.mock('../rewardService', () => ({ walletBalanceChanged: () => {} }));
jest.mock('../hiddenAccounts', () => ({ isHiddenAccount: (u) => u.isTestAccount === true }));

const sc = require('../storeCustomers');
const venue = { venueId: 'v1', venueName: 'Fresh Monkee' };

beforeEach(() => {
  Object.keys(users).forEach((k) => delete users[k]);
  events.length = 0;
});

test('list: counts healed from the ledger once, email only when shared, test accounts hidden, latest first', async () => {
  users.a = { displayName: 'Ann', email: 'ann@x.com', rewardPointsByVenue: { v1: { points: 50, sharedWithStore: '2026-11-01' } } };
  users.b = { displayName: 'Bob', email: 'bob@x.com', rewardPointsByVenue: { v1: { points: 25, purchases: 1, rewardsClaimed: 0, lastScanAt: '2026-11-02', countsBackfilled: true } } };
  users.t = { displayName: 'Test', isTestAccount: true, rewardPointsByVenue: { v1: { points: 5 } } };
  events.push(
    { userId: 'a', venueId: 'v1', type: 'venue_visit', createdAt: '2026-10-01' },
    { userId: 'a', venueId: 'v1', type: 'venue_visit', createdAt: '2026-10-05' },
    { userId: 'a', venueId: 'v1', type: 'redemption', createdAt: '2026-10-06' }
  );

  const rows = await sc.listCustomers(venue);

  expect(rows.map((r) => r.user.displayName)).toEqual(['Bob', 'Ann']);
  expect(rows[1]).toMatchObject({ purchases: 2, rewardsClaimed: 1, lastScanAt: '2026-10-05', email: 'ann@x.com', sharedWithStore: true });
  expect(rows[0].email).toBeNull();
  expect(users.a.rewardPointsByVenue.v1.countsBackfilled).toBe(true);
});

test('remove zeroes the points and keeps them; restore gives them back', async () => {
  users.a = { rewardPoints: 80, rewardPointsByVenue: { v1: { points: 50 }, v2: { points: 30 } } };

  await sc.removeCustomer(venue, 'a');
  expect(users.a.rewardPoints).toBe(30);
  expect(users.a.rewardPointsByVenue.v1).toMatchObject({ points: 0, removedPoints: 50 });
  expect(await sc.isRemoved('a', 'v1')).toBe(true);

  await sc.removeCustomer(venue, 'a'); // twice is once
  expect(users.a.rewardPoints).toBe(30);

  await sc.restoreCustomer(venue, 'a');
  expect(users.a.rewardPoints).toBe(80);
  expect(users.a.rewardPointsByVenue.v1.points).toBe(50);
  expect(users.a.rewardPointsByVenue.v1.removedFromRewards).toBeUndefined();
  expect(await sc.isRemoved('a', 'v1')).toBe(false);
});

test('share records the date on the store bucket', async () => {
  users.a = { rewardPointsByVenue: { v1: { points: 10 } } };
  await sc.shareWithStore('a', venue);
  expect(users.a.rewardPointsByVenue.v1.sharedWithStore).toEqual(expect.any(String));
});
