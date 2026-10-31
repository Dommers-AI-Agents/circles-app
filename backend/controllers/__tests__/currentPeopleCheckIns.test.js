// Check-ins (and the answers on them) show people as they are NOW.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue,
  GeoPoint: class {}
}));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));
jest.mock('../../services/notificationService', () => ({ sendToUser: jest.fn() }));
jest.mock('../../services/checkInVisibility', () => ({ isCheckInVisibleTo: async () => true }));
jest.mock('../../services/viewerContext', () => ({ buildViewerContext: async () => ({}) }));
jest.mock('../../services/activityPrivacy', () => ({
  allowedAudiences: () => ({}), qualifyingAudiences: () => null, loadActivityPrivacyByActor: async () => new Map()
}));

const controller = require('../checkInController');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const future = new Date(Date.now() + 3600e3).toISOString();
const call = async (handler, req) => {
  let body;
  const res = { status() { return this; }, json(b) { body = b; return this; } };
  await handler({ params: {}, query: {}, ...req }, res);
  return body;
};

beforeEach(async () => {
  for (const n of ['users', 'checkIns']) mockDb.rows(n).clear();
  await put('users', 'sal', { displayName: 'Sal Sgroi', profilePicture: 'https://x/sal.jpg' });
  await put('users', 'britt', { displayName: 'Brittany S', profilePicture: 'https://x/britt.jpg' });
  await put('checkIns', 'k1', { userId: 'sal', userName: 'Salvatore', userPhoto: 'https://x/old.jpg', placeId: 'p1', placeName: 'Bar',
    active: true, endTime: future, createdAt: '2026-10-02',
    responses: [{ userId: 'britt', userName: 'Britt', userPhoto: null, response: 'going' }, { userId: 'gone', userName: 'Old Name', response: 'interested' }] });
  await put('checkIns', 'k2', { userId: 'gone', userName: 'Ghost', userPhoto: 'https://x/g.jpg', placeId: 'p1', placeName: 'Bar',
    active: true, endTime: future, createdAt: '2026-10-01' });
});

test('active feed: current owner and responder names; deleted accounts keep stored values', async () => {
  const body = await call(controller.getActiveCheckIns, { user: { uid: 'viewer' } });
  const byId = Object.fromEntries(body.data.map((c) => [c.id, c]));
  expect(byId.k1).toMatchObject({ userName: 'Sal Sgroi', userPhoto: 'https://x/sal.jpg' });
  expect(byId.k1.responses).toEqual([
    { userId: 'britt', userName: 'Brittany S', userPhoto: 'https://x/britt.jpg', response: 'going' },
    { userId: 'gone', userName: 'Old Name', response: 'interested' }
  ]);
  expect(byId.k2).toMatchObject({ userName: 'Ghost', userPhoto: 'https://x/g.jpg' });
});

test('at a place, my own, and the summary\'s friends-out row are current too', async () => {
  const at = await call(controller.getCheckInsAtPlace, { user: { uid: 'viewer' }, params: { placeId: 'p1' } });
  expect(at.data.find((c) => c.id === 'k1').userName).toBe('Sal Sgroi');
  const mine = await call(controller.getMyActiveCheckIns, { user: { uid: 'sal' } });
  expect(mine.data[0].responses[0].userName).toBe('Brittany S');
  const summary = await call(controller.getMySummary, { user: { uid: 'viewer' } });
  expect(summary.data.friendsOut.find((f) => f.userId === 'sal')).toMatchObject({ displayName: 'Sal Sgroi', profilePicture: 'https://x/sal.jpg' });
});
