const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { rankSuggestedUsers, viewerCenter } = require('../localPeople');

test('core first, then favorites nearby, then place count', () => {
  const ranked = rankSuggestedUsers([
    { id: 'big', _actualPlacesCount: 300 },
    { id: 'local', _actualPlacesCount: 5, _localCount: 4 },
    { id: 'core', _isCore: true, _actualPlacesCount: 1 },
    { id: 'localer', _actualPlacesCount: 2, _localCount: 9 }
  ]);
  expect(ranked.map(u => u.id)).toEqual(['core', 'localer', 'local', 'big']);
});

test('a GPS fix is the centre; nothing known means Charlotte', async () => {
  const gps = await viewerCenter('u1', { lastKnownLocation: { latitude: 40.2, longitude: -74 } });
  expect(gps).toEqual({ latitude: 40.2, longitude: -74, isDefault: false });
  const none = await viewerCenter('u2', {});
  expect(none).toMatchObject({ latitude: 35.2271, longitude: -80.8431, isDefault: true });
});
