// Wes, 2026-11-27: Settings → Join FavCircles Code said "wasn't found". The
// admin store list was capped at the newest 200; at 203 stores the oldest
// (the Join code among them) silently dropped off.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};

test('every store is listed, the oldest (the Join FavCircles code) included', async () => {
  const day = (n) => new Date(Date.UTC(2026, 7, 17) + n * 3600e3).toISOString();
  await mockDb.collection('stickerVenues').doc('joinus').set({ venueName: 'FavCircles', genericJoin: true, createdAt: day(0) });
  for (let i = 1; i <= 204; i += 1) {
    await mockDb.collection('stickerVenues').doc(`v${i}`).set({ venueName: `Store ${i}`, createdAt: day(i) });
  }
  const { listVenues } = require('../venues/venueAdminController');
  const out = res();
  await listVenues({ user: { uid: 'admin' } }, out);
  const { venues, count, truncated } = out.json.mock.calls[0][0].data;
  expect(count).toBe(205);
  expect(truncated).toBe(false);
  expect(venues[0].venueId).toBe('v204');
  expect(venues.some((v) => v.venueId === 'joinus' && v.genericJoin)).toBe(true);
});
