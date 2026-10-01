// security audit 2026-10-01: with no expected service account or audience,
// OIDC must fail closed instead of accepting any Google account's token.

const mockVerifyIdToken = jest.fn();
jest.mock('google-auth-library', () => ({
  OAuth2Client: jest.fn().mockImplementation(() => ({ verifyIdToken: mockVerifyIdToken }))
}));

const { verifyScheduler } = require('../verifyScheduler');

const ENV_KEYS = ['SCHEDULER_SECRET', 'SCHEDULER_OIDC_AUDIENCE', 'SCHEDULER_SERVICE_ACCOUNT'];
const saved = {};

const run = async (token) => {
  const req = {
    originalUrl: '/api/tasks/x',
    ip: '1.2.3.4',
    get: (h) => (h === 'Authorization' && token ? `Bearer ${token}` : undefined)
  };
  const res = { statusCode: 200 };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  const next = jest.fn();
  await verifyScheduler(req, res, next);
  return { res, next };
};

beforeEach(() => {
  ENV_KEYS.forEach((k) => { saved[k] = process.env[k]; delete process.env[k]; });
  mockVerifyIdToken.mockReset();
  jest.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => {
  ENV_KEYS.forEach((k) => { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; });
  jest.restoreAllMocks();
});

const googleToken = (email) => mockVerifyIdToken.mockResolvedValue({
  getPayload: () => ({ email, email_verified: true })
});

test('no SA and no audience configured: any OIDC token is refused without verifying', async () => {
  googleToken('random@gmail.com');
  const { res, next } = await run('some.google.jwt');
  expect(res.statusCode).toBe(403);
  expect(next).not.toHaveBeenCalled();
  expect(mockVerifyIdToken).not.toHaveBeenCalled();
});

test('secret header path is unchanged', async () => {
  process.env.SCHEDULER_SECRET = 'shh';
  const { next } = await run('shh');
  expect(next).toHaveBeenCalled();
});

test('production config: the scheduler service account passes', async () => {
  process.env.SCHEDULER_OIDC_AUDIENCE = 'https://api.example.com';
  process.env.SCHEDULER_SERVICE_ACCOUNT = 'circles-scheduler@proj.iam.gserviceaccount.com';
  googleToken('circles-scheduler@proj.iam.gserviceaccount.com');
  const { next } = await run('jwt');
  expect(next).toHaveBeenCalled();
  expect(mockVerifyIdToken).toHaveBeenCalledWith({ idToken: 'jwt', audience: 'https://api.example.com' });
});

test('production config: another Google account is refused', async () => {
  process.env.SCHEDULER_OIDC_AUDIENCE = 'https://api.example.com';
  process.env.SCHEDULER_SERVICE_ACCOUNT = 'circles-scheduler@proj.iam.gserviceaccount.com';
  googleToken('attacker@gmail.com');
  const { res, next } = await run('jwt');
  expect(res.statusCode).toBe(403);
  expect(next).not.toHaveBeenCalled();
});

test('no token at all is refused', async () => {
  const { res } = await run(null);
  expect(res.statusCode).toBe(403);
});
