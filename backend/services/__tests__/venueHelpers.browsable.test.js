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
