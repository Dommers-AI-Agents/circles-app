// One list of place categories; every place that names categories in words
// must cover only that list (Wes, 2026-10-31). The weekly email used the key
// `health` for `healthcare` and the digest named a `beauty` category that
// doesn't exist — this test fails on that kind of drift.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  getMessaging: () => ({}),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const { PLACE_CATEGORY_IDS, AUTO_CATEGORY_IDS } = require('../placeCategories');
const { ALL_CATEGORIES, AUTO_CATEGORIES } = require('../../services/placeCategoryDerivation');
const { VALID_CATEGORIES } = require('../../services/venueDetailsService');
const { CATEGORY_WORDS } = require('../../services/weeklyEmail/html');
const { CATEGORY_PLURAL } = require('../../services/mapDigestService');
const { CATEGORY_LABELS } = require('../../services/suggestionEngine');

test('derivation, validation and the details editor use the one list', () => {
  expect(ALL_CATEGORIES).toEqual(PLACE_CATEGORY_IDS);
  expect(AUTO_CATEGORIES).toEqual(AUTO_CATEGORY_IDS);
  expect(VALID_CATEGORIES).toEqual(AUTO_CATEGORY_IDS);
});

test.each([
  ['weekly email', CATEGORY_WORDS],
  ['map digest', CATEGORY_PLURAL],
  ['suggestions', CATEGORY_LABELS]
])('%s labels name only real categories', (_, labels) => {
  for (const key of Object.keys(labels)) expect(PLACE_CATEGORY_IDS).toContain(key);
});
