// App Review and test accounts never show up where people find each other
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { isHiddenAccount } = require('../hiddenAccounts');
const { findUsersByName, userSearchFields } = require('../userSearchService');

test('flagged, listed, fake, merged and deactivated accounts are hidden', () => {
  expect(isHiddenAccount({ email: 'AppReview@favcircles.com' })).toBe(true);
  expect(isHiddenAccount({ email: 'phototest@favcircles.com' })).toBe(true);
  expect(isHiddenAccount({ email: 'x@privaterelay.appleid.com', isTestAccount: true })).toBe(true);
  expect(isHiddenAccount({ isFakeProfile: true })).toBe(true);
  expect(isHiddenAccount({ mergedInto: 'abc' })).toBe(true);
  expect(isHiddenAccount({ active: false })).toBe(true);
  expect(isHiddenAccount({ email: 'brittanyvans@gmail.com', displayName: 'Brittany R' })).toBe(false);
});

test('user search never sees test accounts, and never keeps an email', async () => {
  const user = (data) => ({ ...data, ...userSearchFields(data) });
  await mockDb.collection('users').doc('real').set(user({ displayName: 'Real Person', email: 'real@gmail.com' }));
  await mockDb.collection('users').doc('rev').set(user({ displayName: 'Real App Review', email: 'appreview@favcircles.com' }));
  await mockDb.collection('users').doc('john').set(user({ displayName: 'Real John', isTestAccount: true }));
  const found = await findUsersByName('real', { db: mockDb });
  expect(found.map(u => u.id)).toEqual(['real']);
  expect(found[0].email).toBeUndefined();
});
