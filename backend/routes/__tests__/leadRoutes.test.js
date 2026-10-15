// Website lead capture: the homepage form and the Instagram link-in-bio page
// (favcircles.com/ig) both post here; the source is remembered.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore();
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  admin: { firestore: { FieldValue: MockFieldValue } }
}));
const mockSendLeadEmail = jest.fn(async () => {});
jest.mock('../../services/emailService', () => ({ sendWebsiteLeadEmail: mockSendLeadEmail }));

const router = require('../leadRoutes');
const handler = router.stack.find((l) => l.route && l.route.path === '/website').route.stack.slice(-1)[0].handle;

const post = async (body) => {
  const res = { statusCode: 200, body: null, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
  await handler({ body }, res);
  return res;
};
const lead = async (email) => (await mockDb.collection('websiteLeads').doc(email.replace(/[/.]/g, '_')).get()).data();

describe('POST /api/leads/website', () => {
  beforeEach(() => mockSendLeadEmail.mockClear());

  it('records an Instagram sign-up and emails once', async () => {
    const res = await post({ email: 'Ana@Example.com', source: 'instagram' });
    expect(res.statusCode).toBe(200);
    expect(mockSendLeadEmail).toHaveBeenCalledWith('ana@example.com');
    expect(await lead('ana@example.com')).toMatchObject({ source: 'instagram', sources: ['instagram'] });
  });

  it('a second sign-up from another page adds the source, keeps the first, sends nothing', async () => {
    await post({ email: 'ben@example.com' });
    await post({ email: 'ben@example.com', source: 'instagram' });
    expect(mockSendLeadEmail).toHaveBeenCalledTimes(1);
    expect(await lead('ben@example.com')).toMatchObject({ source: 'website', sources: ['website', 'instagram'] });
  });

  it('an unknown source counts as the website; a bad email is refused', async () => {
    await post({ email: 'cy@example.com', source: '<script>' });
    expect((await lead('cy@example.com')).source).toBe('website');
    expect((await post({ email: 'nope' })).statusCode).toBe(400);
  });
});
