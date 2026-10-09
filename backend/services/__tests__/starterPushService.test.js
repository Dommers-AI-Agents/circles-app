jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), FieldValue: {} }));
const { starterPushFor } = require('../starterPushService');

describe('first-week pushes', () => {
  test('day 1 only when they have no place yet', () => {
    expect(starterPushFor(1, { realPlaces: 0 })).toMatchObject({ key: 'starter_push_map', type: 'starter_map' });
    expect(starterPushFor(1, { realPlaces: 1 })).toBeNull();
  });
  test('day 2 only while following nobody beyond the default accounts', () => {
    expect(starterPushFor(2, { followingOthers: 0 })).toMatchObject({ key: 'starter_push_follow', type: 'starter_follow' });
    expect(starterPushFor(2, { followingOthers: 3 })).toBeNull();
  });
  test('day 4 nudges a small map', () => {
    expect(starterPushFor(4, { realPlaces: 1 }).body).toMatch(/1 place\./);
    expect(starterPushFor(4, { realPlaces: 3 })).toBeNull();
  });
  test('other days are quiet', () => {
    for (const d of [0, 3, 5, 6, 7]) expect(starterPushFor(d, {})).toBeNull();
  });
});
