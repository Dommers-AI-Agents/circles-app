// Inner Circle access resolution: who has put the viewer on a list, and which
// lists. Every read surface goes through this, so a crash here blanks a
// person's whole feed — which is what happened when isSameUser went missing.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const { getInnerCircleGrantorLists, getInnerCircleGrantorIds } = require('../networkAccess');

const WES = '111';
const BRITT = '222';
const SAL = '333';

beforeEach(() => mockDb.rows(COLLECTIONS.USERS).clear());

test('a viewer on named lists gets each grantor with the lists they are on', async () => {
  await mockDb.collection(COLLECTIONS.USERS).doc(WES).set({
    innerCircle: [SAL, BRITT],
    innerCircles: [
      { id: 'family', name: 'Family', userIds: [SAL, BRITT] },
      { id: 'work', name: 'Work', userIds: [BRITT] }
    ]
  });
  // A legacy grantor with only the flat field lands on the default list.
  await mockDb.collection(COLLECTIONS.USERS).doc(BRITT).set({ innerCircle: [SAL] });
  await mockDb.collection(COLLECTIONS.USERS).doc(SAL).set({ innerCircle: [] });

  const lists = await getInnerCircleGrantorLists(SAL);
  expect([...lists.get(WES)]).toEqual(['family']);
  expect(lists.get(BRITT).size).toBe(1);
  expect(lists.has(SAL)).toBe(false);

  const ids = await getInnerCircleGrantorIds(SAL);
  expect([...ids].sort()).toEqual([WES, BRITT]);
});

test('nobody has listed the viewer → empty, not an error', async () => {
  expect((await getInnerCircleGrantorLists(SAL)).size).toBe(0);
  expect((await getInnerCircleGrantorLists(null)).size).toBe(0);
});
