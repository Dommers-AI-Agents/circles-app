// Editing a comment: the author's new words land on the comment and on the
// feed row that quotes it; nobody else's request changes anything.
const store = {};
const fakeDoc = (col, id) => ({
  id,
  exists: !!(store[col] && store[col][id]),
  data: () => store[col][id],
  ref: { update: async (patch) => applyPatch(store[col][id], patch) }
});
function applyPatch(target, patch) {
  for (const [key, value] of Object.entries(patch)) {
    const parts = key.split('.');
    let at = target;
    while (parts.length > 1) { const p = parts.shift(); at[p] = at[p] || {}; at = at[p]; }
    at[parts[0]] = value;
  }
}
const db = {
  collection: (col) => ({
    doc: (id) => ({ get: async () => fakeDoc(col, id), update: async (patch) => applyPatch(store[col][id], patch) }),
    where() { return this; },
    get: async () => ({ docs: Object.keys(store[col] || {}).map((id) => fakeDoc(col, id)) })
  })
};
jest.mock('../../config/firebase', () => ({ admin: {}, getFirestore: () => db }));
jest.mock('../notificationService', () => ({}));
jest.mock('../piggyBankService', () => ({}));
jest.mock('../globalPlaceResolver', () => ({ ensureGlobalPlaceLink: async () => null }));

const { editPlaceComment } = require('../placeCommentService');

beforeEach(() => {
  Object.keys(store).forEach((k) => delete store[k]);
  Object.assign(store, {
    placeComments: { c1: { userId: 'ann', placeId: 'p1', globalPlaceId: 'g1', text: 'Good cofee', likes: ['bob'], likesCount: 1, replyCount: 2, createdAt: '2026-11-24T00:00:00.000Z' } },
    places: { p1: { addedBy: 'bob', globalPlaceId: 'g1' }, p2: { addedBy: 'carol', globalPlaceId: 'g1' } },
    users: { ann: { displayName: 'Ann' } },
    activities: { a1: { type: 'place_commented', actorId: 'ann', targetId: 'p1', metadata: { commentId: 'c1', comment: 'Good cofee' } } }
  });
});

test('the author\'s new words replace the old, likes and replies stay, and the feed row follows', async () => {
  const out = await editPlaceComment({ placeId: 'p2', commentId: 'c1', userId: 'ann', text: '  Good coffee  ' });
  expect(out).toMatchObject({ text: 'Good coffee', likesCount: 1, replyCount: 2, createdAt: '2026-11-24T00:00:00.000Z' });
  expect(out.editedAt).toEqual(expect.any(String));
  expect(out.user).toBeTruthy();
  expect(store.placeComments.c1.text).toBe('Good coffee');
  expect(store.activities.a1.metadata.comment).toBe('Good coffee');
});

test('the same words again are not an edit', async () => {
  const out = await editPlaceComment({ placeId: 'p1', commentId: 'c1', userId: 'ann', text: 'Good cofee' });
  expect(out.editedAt).toBeUndefined();
});

test('refusals: empty, too long, not the author (even the save\'s owner), another venue, missing', async () => {
  const edit = (over) => editPlaceComment({ placeId: 'p1', commentId: 'c1', userId: 'ann', text: 'New', ...over });
  await expect(edit({ text: '   ' })).rejects.toMatchObject({ status: 400, code: 'TEXT_REQUIRED' });
  await expect(edit({ text: 'x'.repeat(2001) })).rejects.toMatchObject({ status: 400, code: 'TEXT_TOO_LONG' });
  await expect(edit({ userId: 'bob' })).rejects.toMatchObject({ status: 403, code: 'NOT_AUTHOR' });
  await expect(edit({ commentId: 'nope' })).rejects.toMatchObject({ status: 404, code: 'COMMENT_NOT_FOUND' });
  await expect(edit({ placeId: 'nope' })).rejects.toMatchObject({ status: 404, code: 'PLACE_NOT_FOUND' });
  store.places.p3 = { addedBy: 'ann', globalPlaceId: 'g9' };
  await expect(edit({ placeId: 'p3' })).rejects.toMatchObject({ status: 400, code: 'WRONG_PLACE' });
  expect(store.placeComments.c1.text).toBe('Good cofee');
});
