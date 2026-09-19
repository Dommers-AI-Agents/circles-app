// The wrapper must send exactly what the inline handlers sent.
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../../services/dailySummaryService', () => ({ sendDailySummaries: jest.fn(async () => {}) }));
jest.mock('../../../services/scheduledNotifications', () => ({ sendDiscoveryPrompts: jest.fn(), sendWeekendRecommendations: jest.fn(), sendReengagementNotifications: jest.fn(async () => ({ sent: 3 })) }));
jest.mock('../../../services/engagementNotificationService', () => ({}));
jest.mock('../../../services/tipsService', () => ({ sendTips: jest.fn(async (args) => ({ echoed: args })) }));
jest.mock('../../../services/milestoneService', () => ({}));
jest.mock('../../../services/suggestionEngine', () => ({ buildAllSuggestions: jest.fn(async () => ({ users: 5 })) }));
jest.mock('../../../services/followSuggestionEmailService', () => ({ run: jest.fn(async () => ({ sent: 1, recipients: [{ email: 'a@b', sampleHtml: '<p>' }] })) }));
jest.mock('../../../services/categorySweep', () => ({ runCategorySweep: jest.fn() }));
jest.mock('../../../services/venueReportsTask', () => ({ sendVenueReports: jest.fn() }));

const tasks = require('../scheduledTasksController');

const fakeRes = () => {
  const res = { statusCode: 200, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
};
const req = (over = {}) => ({ query: {}, body: {}, params: {}, ...over });

beforeAll(() => { jest.spyOn(console, 'log').mockImplementation(() => {}); jest.spyOn(console, 'error').mockImplementation(() => {}); });

test('a plain job answers success + message + timestamp', async () => {
  const res = fakeRes();
  await tasks.dailySummary(req(), res);
  expect(res.statusCode).toBe(200);
  expect(Object.keys(res.body)).toEqual(['success', 'message', 'timestamp']);
  expect(res.body).toMatchObject({ success: true, message: 'Daily summaries sent successfully' });
});

test('a job with a result nests it; one with a report spreads it', async () => {
  let res = fakeRes();
  await tasks.reengagement(req(), res);
  expect(res.body).toMatchObject({ success: true, message: 'Reengagement notifications sent successfully', result: { sent: 3 } });
  res = fakeRes();
  await tasks.buildSuggestions(req({ query: { dryRun: 'true' } }), res);
  expect(res.body).toMatchObject({ success: true, message: 'Suggestion rebuild dry run completed', users: 5 });
});

test('tips reads dryRun/userId/force from query or body', async () => {
  const res = fakeRes();
  await tasks.tips(req({ body: { dryRun: true, userId: 'u1' }, query: { force: 'true' } }), res);
  expect(res.body.result).toEqual({ echoed: { dryRun: true, userId: 'u1', force: true } });
});

test('follow suggestions strips sampleHtml from recipients', async () => {
  const res = fakeRes();
  await tasks.followSuggestions(req(), res);
  expect(res.body).toMatchObject({ message: 'Follow-suggestion emails sent', sent: 1, recipients: [{ email: 'a@b' }] });
  expect(res.body.recipients[0].sampleHtml).toBeUndefined();
});

test('a failing job answers 500 with the job\'s failure text and the error', async () => {
  require('../../../services/dailySummaryService').sendDailySummaries.mockRejectedValueOnce(new Error('smtp down'));
  const res = fakeRes();
  await tasks.dailySummary(req(), res);
  expect(res.statusCode).toBe(500);
  expect(res.body).toEqual({ success: false, error: 'Failed to send daily summaries', details: 'smtp down' });
});

test('resolve-claim keeps its own validation', async () => {
  const res = fakeRes();
  await tasks.piggyBankResolveClaim(req(), res);
  expect(res.statusCode).toBe(400);
});
