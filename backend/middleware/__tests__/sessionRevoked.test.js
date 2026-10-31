// Sessions minted before an account's sessionsValidAfter are refused: an
// instant App Clip account claimed by its email's proven owner (2026-10-31)
const jwt = require('jsonwebtoken');
let mockUserDoc = {};
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({
      doc: (id) => ({
        id,
        get: async () => ({ id, exists: true, ref: { id }, data: () => mockUserDoc }),
        update: async () => {}
      })
    })
  })
}));
jest.mock('../../services/userSearchService', () => ({ healUserSearchFields: () => Promise.resolve() }));
process.env.JWT_SECRET = 'test-secret';
const { protect } = require('../firebaseAuth');

const run = async (iatSeconds) => {
  const token = jwt.sign({ uid: 'u1', email: 'a@example.com', iat: iatSeconds }, 'test-secret');
  const req = { method: 'POST', headers: { authorization: `Bearer ${token}` } };
  let status = 200; let body = null; let nextCalled = false;
  const res = { status(s) { status = s; return this; }, json(b) { body = b; return this; } };
  await protect(req, res, () => { nextCalled = true; });
  return { status, body, nextCalled };
};

test('a session from before sessionsValidAfter is refused; one from after works', async () => {
  mockUserDoc = { email: 'a@example.com', sessionsValidAfter: 2_000_000_000 * 1000 };
  const old = await run(1_999_999_999);
  expect(old).toMatchObject({ status: 401, nextCalled: false });
  expect(old.body.code).toBe('session_revoked');
  const fresh = await run(2_000_000_000);
  expect(fresh.nextCalled).toBe(true);
});

test('accounts without the field are untouched', async () => {
  mockUserDoc = { email: 'a@example.com' };
  expect((await run(1_000)).nextCalled).toBe(true);
});
