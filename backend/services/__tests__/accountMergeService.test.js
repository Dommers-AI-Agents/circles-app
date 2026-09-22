// Two accounts of one person become one: the older survives whichever way
// the ids were passed, every reference follows, nothing is deleted, and the
// new account's empty defaults and duplicate welcome request are folded.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { mergeAccounts, chooseSurvivor } = require('../accountMergeService');

const put = (col, id, data) => mockDb.rows(col).set(id, data);
const get = (col, id) => mockDb.rows(col).get(id);
beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
});

const OLD = 'google-2025';
const NEW = 'apple-2026';
const WES = 'wes';

function seedSal() {
  put('users', OLD, {
    email: 'sal@gmail.com', displayName: 'Salvatore A Sgroi', createdAt: '2025-06-25T09:55:12.193Z',
    linkedProviders: { google: OLD }, followers: [WES, 'linda'], following: [WES],
    subscriptionTier: 'premium'
  });
  put('users', NEW, {
    email: 'x@privaterelay.appleid.com', displayName: 'Apple User', createdAt: '2026-09-22T13:39:01.452Z',
    linkedProviders: { apple: '001846.abc' }, followers: [WES], following: [WES],
    subscriptionStatus: 'active', appleOriginalTransactionId: '7000'
  });
  put('users', WES, { displayName: 'Wesley', followers: [OLD, NEW], following: [OLD, NEW], innerCircle: [NEW] });
  put('users', 'linda', { displayName: 'Linda', followers: [], following: [OLD] });

  put('circles', 'eateries', { owner: NEW, name: 'Eateries', createdAt: '2025-06-21' });
  put('circles', 'want', { owner: NEW, name: 'Want to Try', isDefaultCircle: true });
  put('circles', 'fav', { owner: NEW, name: 'Favorite Local Spots', isDefaultCircle: true });
  put('circles', 'diners', { owner: OLD, name: 'Diners' });
  put('places', 'tommys', { addedBy: NEW, circleId: 'eateries', name: "Tommy's" });
  put('places', 'gone', { addedBy: NEW, circleId: 'fav', name: 'Old sample', deletedAt: '2025-07-01' });
  put('placeComments', 'c1', { userId: NEW, text: 'Excellent atmosphere' });
  put('checkIns', 'k1', { userId: NEW });
  put('placeVideos', 'v1', { userId: NEW });
  put('notifications', 'n1', { userId: NEW, type: 'connection_request' });
  put('connections', 'welcome-new', { userId: WES, connectedUserId: NEW, status: 'pending' });
  put('connections', 'welcome-old', { userId: WES, connectedUserId: OLD, status: 'accepted' });
  put('connections', 'other', { userId: NEW, connectedUserId: 'joe', status: 'pending' });
  put('globalPlaces', 'g1', { likes: [NEW, OLD], likesCount: 2 });
}

describe('chooseSurvivor', () => {
  test('the older account survives whichever way the ids were passed', () => {
    const a = { id: 'a', createdAt: '2026-01-01' };
    const b = { id: 'b', createdAt: '2025-01-01' };
    expect(chooseSurvivor(a, b)).toEqual({ primary: b, secondary: a, swapped: true });
    expect(chooseSurvivor(b, a)).toEqual({ primary: b, secondary: a, swapped: false });
  });
});

describe('mergeAccounts', () => {
  test('signed into the new account and asking to keep it still keeps the old one', async () => {
    seedSal();
    const result = await mergeAccounts({ primaryId: NEW, secondaryId: OLD });
    expect(result.swapped).toBe(true);
    expect(result.primaryId).toBe(OLD);

    const sal = get('users', OLD);
    expect(sal.displayName).toBe('Salvatore A Sgroi');
    expect(sal.email).toBe('sal@gmail.com');
    expect(sal.linkedProviders).toEqual({ google: OLD, apple: '001846.abc' });
    expect(sal.alternateEmails).toEqual(['x@privaterelay.appleid.com']);
    expect([...sal.followers].sort()).toEqual([WES, 'linda'].sort());
    expect(sal.followersCount).toBe(2);
    // Entitlement the survivor lacked carries over; what it had stays
    expect(sal.subscriptionTier).toBe('premium');
    expect(sal.subscriptionStatus).toBe('active');
    expect(sal.appleOriginalTransactionId).toBe('7000');

    const folded = get('users', NEW);
    expect(folded.mergedInto).toBe(OLD);
    expect(folded.active).toBe(false);
  });

  test('every reference follows; nothing is deleted', async () => {
    seedSal();
    await mergeAccounts({ primaryId: OLD, secondaryId: NEW });
    expect(get('circles', 'eateries').owner).toBe(OLD);
    expect(get('places', 'tommys').addedBy).toBe(OLD);
    expect(get('places', 'gone').addedBy).toBe(OLD);
    expect(get('placeComments', 'c1').userId).toBe(OLD);
    expect(get('checkIns', 'k1').userId).toBe(OLD);
    expect(get('placeVideos', 'v1').userId).toBe(OLD);
    expect(get('notifications', 'n1').userId).toBe(OLD);
    expect(get('connections', 'other').userId).toBe(OLD);
    expect(get('users', 'linda').following).toEqual([OLD]);
  });

  test('the follow graph and likes collapse to one id, counts corrected', async () => {
    seedSal();
    await mergeAccounts({ primaryId: OLD, secondaryId: NEW });
    const wes = get('users', WES);
    expect(wes.followers).toEqual([OLD]);
    expect(wes.following).toEqual([OLD]);
    expect(wes.innerCircle).toEqual([OLD]);
    expect(get('globalPlaces', 'g1').likes).toEqual([OLD]);
    expect(get('globalPlaces', 'g1').likesCount).toBe(1);
  });

  test('empty default circles and the duplicate welcome request are folded', async () => {
    seedSal();
    const result = await mergeAccounts({ primaryId: OLD, secondaryId: NEW });
    // "Want to Try" is empty → folded; "Favorite Local Spots" holds only a
    // deleted place → also empty → folded; "Eateries" has a live place → moves
    expect(get('circles', 'want').deletedAt).toBeTruthy();
    expect(get('circles', 'want').owner).toBe(NEW);
    expect(get('circles', 'fav').deletedAt).toBeTruthy();
    expect(get('circles', 'eateries').deletedAt).toBeUndefined();
    expect(result.counts.defaultCirclesFolded).toBe(2);
    expect(result.counts.circlesMoved).toBe(1);
    // Wes already has a connection with the old account
    expect(get('connections', 'welcome-new').status).toBe('merged');
    expect(get('connections', 'welcome-new').connectedUserId).toBe(NEW);
    expect(get('connections', 'welcome-old').status).toBe('accepted');
    expect(result.counts.connectionsFolded).toBe(1);
    expect(result.counts.connections).toBe(1);
  });

  test('a dry run plans everything and writes nothing', async () => {
    seedSal();
    const result = await mergeAccounts({ primaryId: NEW, secondaryId: OLD, dryRun: true });
    expect(result.primaryId).toBe(OLD);
    expect(result.counts.places).toBe(2);
    expect(result.operations).toBeGreaterThan(5);
    expect(get('places', 'tommys').addedBy).toBe(NEW);
    expect(get('users', NEW).mergedInto).toBeUndefined();
    expect(get('users', OLD).linkedProviders).toEqual({ google: OLD });
  });

  test('refuses an account that was already merged', async () => {
    seedSal();
    await mergeAccounts({ primaryId: OLD, secondaryId: NEW });
    await expect(mergeAccounts({ primaryId: OLD, secondaryId: NEW })).rejects.toMatchObject({ status: 409 });
  });
});
