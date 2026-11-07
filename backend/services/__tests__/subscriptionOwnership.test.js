// One App Store subscription, one FavCircles account (2026-11-07)
jest.mock('firebase-admin/firestore', () => ({ FieldValue: { delete: () => '__delete__' } }));
const own = require('../subscriptionOwnership');

const makeDb = (users) => ({
  collection: () => ({
    where: (field, op, value) => ({
      limit: () => ({
        get: async () => ({
          docs: Object.entries(users).filter(([, u]) => u[field] === value).map(([id, u]) => ({ id, data: () => u }))
        })
      })
    }),
    doc: (id) => ({ update: async (u) => { users[id] = { ...users[id], ...u }; } })
  })
});

test('masks the other account\'s email', () => {
  expect(own.maskEmail('sgroiwes@gmail.com')).toBe('s•••@gmail.com');
  expect(own.maskEmail(null)).toBeNull();
});

test('a subscription nobody holds applies', async () => {
  const db = makeDb({});
  expect(await own.decide(db, { originalTransactionId: 't1', userId: 'new' })).toEqual({ action: 'apply' });
});

test('another account holding it blocks, unless they ask to move it', async () => {
  const users = { main: { appleOriginalTransactionId: 't1', email: 'sgroiwes@gmail.com', subscriptionStatus: 'active' } };
  const db = makeDb(users);
  expect(await own.decide(db, { originalTransactionId: 't1', userId: 'tester' }))
    .toEqual({ action: 'blocked', emailHint: 's•••@gmail.com' });
  expect(users.main.subscriptionStatus).toBe('active');

  expect(await own.decide(db, { originalTransactionId: 't1', userId: 'tester', transfer: true }))
    .toEqual({ action: 'moved', from: 'main' });
  expect(users.main.subscriptionStatus).toBe('expired');
  expect(users.main.appleOriginalTransactionId).toBe('__delete__');
  expect(users.main.subscriptionMovedTo).toBe('tester');
});

test('the account that already holds it keeps applying; merged-away accounts don\'t count', async () => {
  const db = makeDb({ old: { appleOriginalTransactionId: 't1', mergedInto: 'main' } });
  expect(await own.decide(db, { originalTransactionId: 't1', userId: 'main', alreadyHeldHere: true })).toEqual({ action: 'apply' });
  expect(await own.decide(db, { originalTransactionId: 't1', userId: 'main' })).toEqual({ action: 'apply' });
});
