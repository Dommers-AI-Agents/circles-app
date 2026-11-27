// Wes, 2026-11-27: a passkey sign-in in Coolidge, AZ replaced his Charlotte
// zipcode. The sign-in response had no `zipcode`, so the app's silent capture
// thought he had none and saved the phone's. Two guards, pinned here.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/zipcodeService', () => ({
  geocodeZipcode: async (zip) => (zip === '85128' ? { city: 'Coolidge', state: 'AZ' } : { city: 'Charlotte', state: 'NC' })
}));

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const fail = (e) => { throw e; };

beforeEach(() => mockDb.rows('users').clear());

describe('PUT /api/users/me with zipcodeIfMissing (the silent capture)', () => {
  const { updateUser } = require('../users/userController');
  const stored = async () => (await mockDb.collection('users').doc('me').get()).data();

  test('keeps a zipcode the person already has', async () => {
    await mockDb.collection('users').doc('me').set({ displayName: 'Wes', zipcode: '28203', location: 'Charlotte, NC' });
    await updateUser({ body: { zipcode: '85128', zipcodeIfMissing: true }, user: { uid: 'me' } }, res(), fail);
    expect(await stored()).toMatchObject({ zipcode: '28203', location: 'Charlotte, NC' });
  });

  test('fills one that is missing', async () => {
    await mockDb.collection('users').doc('me').set({ displayName: 'Wes' });
    await updateUser({ body: { zipcode: '85128', zipcodeIfMissing: true }, user: { uid: 'me' } }, res(), fail);
    expect(await stored()).toMatchObject({ zipcode: '85128', location: 'Coolidge, AZ' });
  });

  test('an explicit edit (no flag) still changes it', async () => {
    await mockDb.collection('users').doc('me').set({ displayName: 'Wes', zipcode: '28203' });
    await updateUser({ body: { zipcode: '85128' }, user: { uid: 'me' } }, res(), fail);
    expect(await stored()).toMatchObject({ zipcode: '85128', location: 'Coolidge, AZ' });
  });
});

describe('sign-in responses carry the zipcode', () => {
  test('authUserPayload', () => {
    const { authUserPayload } = require('../../services/newAccountService');
    expect(authUserPayload({ displayName: 'Wes', zipcode: '28203' }, 'me').zipcode).toBe('28203');
    expect(authUserPayload({ displayName: 'New' }, 'new').zipcode).toBeNull();
  });
});
