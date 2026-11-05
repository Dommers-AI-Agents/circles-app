jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../globalPlaceResolver', () => ({}));
const { isBrowsableBy } = require('../venueHelpers');

describe('isBrowsableBy: demo stores stay out of customer browse lists', () => {
  const testStore = { venueId: 'v1', isTestStore: true, ownerUserId: 'owner', managerUserIds: ['mgr'] };

  test('a normal store is browsable by anyone', () => {
    expect(isBrowsableBy({ venueId: 'v2', ownerUserId: 'owner' }, 'someone')).toBe(true);
    expect(isBrowsableBy({ venueId: 'v2' }, null)).toBe(true);
  });

  test('a test store is hidden from customers', () => {
    expect(isBrowsableBy(testStore, 'customer')).toBe(false);
    expect(isBrowsableBy(testStore, null)).toBe(false);
  });

  test('a test store is still browsable by its owner and managers', () => {
    expect(isBrowsableBy(testStore, 'owner')).toBe(true);
    expect(isBrowsableBy(testStore, 'mgr')).toBe(true);
  });
});

test('a super-user sees test stores (to check demo promos); everyone else still does not', () => {
  const { isBrowsableBy } = require('../venueHelpers');
  const testStore = { venueId: 'v1', isTestStore: true, ownerUserId: 'owner', managerUserIds: [] };
  expect(isBrowsableBy(testStore, 'wes', { isSuperUser: true })).toBe(true);
  expect(isBrowsableBy(testStore, 'customer', { isSuperUser: false })).toBe(false);
  expect(isBrowsableBy(testStore, 'customer')).toBe(false);
});
