// Activity comments and reactions show the person's CURRENT name and photo
// (from their users record), not the copy written when they commented
// (Wes, 2026-10-31: "stored in the db and pulled from one place").
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/notificationService', () => ({ sendToUser: jest.fn() }));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));

const controller = require('../activityInteractionController');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const call = async (handler, req) => {
  let body;
  const res = { status() { return this; }, json(b) { body = b; return this; } };
  await handler({ params: {}, query: {}, user: { uid: 'viewer' }, ...req }, res);
  return body;
};

beforeEach(async () => {
  for (const n of ['users', 'activityComments', 'activityReactions']) mockDb.rows(n).clear();
  await put('users', 'u1', { displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
});

test('comments: renamed commenter shows the new name; a deleted account keeps the stored one', async () => {
  await put('activityComments', 'c1', { activityId: 'a1', parentCommentId: null, userId: 'u1', userName: 'Salvatore', userPhoto: 'https://x/old.jpg', text: 'hi', createdAt: '2026-10-01' });
  await put('activityComments', 'c2', { activityId: 'a1', parentCommentId: null, userId: 'gone', userName: 'Old Name', userPhoto: null, text: 'yo', createdAt: '2026-10-02' });
  const body = await call(controller.getComments, { params: { activityId: 'a1' } });
  const byId = Object.fromEntries(body.data.map((c) => [c.id, c]));
  expect(byId.c1).toMatchObject({ userName: 'Sal Sgroi', userPhoto: 'https://x/new.jpg', text: 'hi' });
  expect(byId.c2).toMatchObject({ userName: 'Old Name', text: 'yo' });
});

test('reactions and reaction details: current name/photo', async () => {
  await put('activityReactions', 'r1', { activityId: 'a1', userId: 'u1', emoji: '🔥', userName: 'Salvatore', userPhoto: 'https://x/old.jpg', createdAt: '2026-10-01' });
  await put('activityReactions', 'r2', { activityId: 'a1', userId: 'gone', emoji: '🔥', userName: 'Old Name', userPhoto: 'https://x/g.jpg', createdAt: '2026-10-02' });
  const list = await call(controller.getReactions, { params: { activityId: 'a1' } });
  expect(list.data.groups[0].users).toEqual(expect.arrayContaining([
    { userId: 'u1', userName: 'Sal Sgroi', userPhoto: 'https://x/new.jpg' },
    { userId: 'gone', userName: 'Old Name', userPhoto: 'https://x/g.jpg' }
  ]));
  const details = await call(controller.getReactionDetails, { params: { activityId: 'a1' } });
  expect(details.data.find((d) => d.userId === 'u1')).toMatchObject({ displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
  expect(details.data.find((d) => d.userId === 'gone')).toMatchObject({ displayName: 'Old Name' });
});
