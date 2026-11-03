// Changing a circle's privacy can bring its places along (Wes, 2026-11-03)
const docs = [];
const updates = [];
const fakeDb = {
  collection: (name) => ({
    doc: (id) => ({ get: async () => ({ exists: name === 'circles' && id === 'c1', data: () => ({ owner: 'wes' }) }) }),
    where: () => ({ select: () => ({ get: async () => ({ docs }) }) })
  }),
  batch: () => ({ update: (ref, data) => updates.push([ref.id, data]), commit: async () => {} })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => fakeDb }));
const { countOwnPrivacy, matchCircle } = require('../circlePlacePrivacy');

const place = (id, addedBy, privacy, extra = {}) => ({ ref: { id }, data: () => ({ addedBy, privacy, ...extra }) });

beforeEach(() => {
  docs.length = 0; updates.length = 0;
  docs.push(
    place('p1', 'wes', 'private'),            // own setting → counted
    place('p2', 'wes', 'followCircle'),       // follows already
    place('p3', 'wes', undefined),            // follows already
    place('p4', 'brittany', 'public'),        // an editor's save: theirs to decide
    place('p5', 'wes', 'public', { deletedAt: '2026-10-01' }) // unsaved
  );
});

test('counts only the owner\'s live places with their own setting', async () => {
  expect(await countOwnPrivacy('c1', 'wes', { db: fakeDb })).toBe(1);
});

test('match sets them to follow the circle', async () => {
  expect(await matchCircle('c1', 'wes', { db: fakeDb })).toBe(1);
  expect(updates).toEqual([['p1', expect.objectContaining({ privacy: 'followCircle', audienceListId: null })]]);
});

test('only the owner may ask', async () => {
  await expect(countOwnPrivacy('c1', 'brittany', { db: fakeDb })).rejects.toMatchObject({ status: 403 });
  await expect(matchCircle('nope', 'wes', { db: fakeDb })).rejects.toMatchObject({ status: 404 });
});
