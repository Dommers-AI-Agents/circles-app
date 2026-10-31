// Dog Park feed posts (and comments, when the caller passes the author) name
// the author as they are NOW.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));

const s = require('../dogPark/shared');

test('the feed shows the author\'s current name and photo', async () => {
  await s.usersCol().doc('ana').set({ displayName: 'Ana Maria', profilePicture: 'https://x/ana.jpg' });
  await s.usersCol().doc('wes').set({ displayName: 'Wes' });
  await s.postsCol().doc('p1').set({ authorId: 'ana', authorName: 'Ana', authorPhotoUrl: 'https://x/old.jpg', status: 'ready', createdAt: '2026-10-30' });
  const doc = await s.postsCol().doc('p1').get();
  const [post] = await s.present([doc], 'wes', { displayName: 'Wes' });
  expect(post).toMatchObject({ authorName: 'Ana Maria', authorPhotoUrl: 'https://x/ana.jpg' });
});

test('without the author record the stored name/photo stand', () => {
  expect(s.toClientPost('p', { authorId: 'gone', authorName: 'Old', authorPhotoUrl: 'https://x/o.jpg' }, 'wes'))
    .toMatchObject({ authorName: 'Old', authorPhotoUrl: 'https://x/o.jpg' });
  expect(s.toClientComment('c', { authorId: 'gone', authorName: 'Old' }, 'wes').authorName).toBe('Old');
  expect(s.toClientComment('c', { authorId: 'ana', authorName: 'Ana' }, 'wes', { displayName: 'Ana Maria', profilePicture: 'https://x/a.jpg' }))
    .toMatchObject({ authorName: 'Ana Maria', authorPhotoUrl: 'https://x/a.jpg' });
});
