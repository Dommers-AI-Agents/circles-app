// How Are You? on the Lock Screen (Wes, 2026-10-30: "persistent notification
// so a user doesn't miss the question"). The question is started as a Live
// Activity by push, ends when answered, gives way to the next one, and a
// phone that shows no display gets the question once more an hour later.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const mockConnections = new Map();
jest.mock('../connectionMap', () => ({ buildConnectionMap: jest.fn(async () => mockConnections) }));
jest.mock('../notificationService', () => {
  const sendToUser = jest.fn(async () => ({ success: true }));
  return { sendToUser, sendToUserWithRecord: jest.fn((userId, payload) => sendToUser(userId, payload)) };
});
jest.mock('../emailService', () => ({ sendEmail: jest.fn(async () => ({})) }));
jest.mock('../liveActivityPush', () => ({ sendLiveActivity: jest.fn(async () => true) }));

const notificationService = require('../notificationService');
const liveActivityPush = require('../liveActivityPush');
const care = require('../careCheckinService');
const { contentState, ATTRIBUTES_TYPE } = require('../careCheckin/liveActivity');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const CHILD = 'child_1';
const PARENT = 'parent_1';
const PLAN = `${CHILD}_${PARENT}`;
const T_0835_NY = new Date('2026-09-19T12:35:00Z');
const T_1305_NY = new Date('2026-09-19T17:05:00Z');
const asks = () => mockDb.rows(COLLECTIONS.CARE_ASKS);
const minutes = (n) => n * 60 * 1000;

async function activePlan() {
  await mockDb.collection(COLLECTIONS.USERS).doc(CHILD).set({ displayName: 'Wes' });
  await mockDb.collection(COLLECTIONS.USERS).doc(PARENT).set({ displayName: 'Mom', notificationPreferences: { timezone: 'America/New_York' } });
  mockConnections.set(PARENT, { status: 'accepted' });
  await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['08:30', '13:00', '19:00'], questions: [] });
  await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: true, timezone: 'America/New_York' });
  notificationService.sendToUser.mockClear();
}

beforeEach(() => {
  for (const name of [COLLECTIONS.CARE_PLANS, COLLECTIONS.CARE_ASKS, COLLECTIONS.USERS, 'careLiveStartTokens']) mockDb.rows(name).clear();
  mockConnections.clear();
  notificationService.sendToUser.mockClear();
  liveActivityPush.sendLiveActivity.mockClear();
  liveActivityPush.sendLiveActivity.mockImplementation(async () => true);
});

test('the content matches the app: question, kind, choice buttons, scale ends, nulls when absent', () => {
  expect(contentState({ questionText: 'How are you feeling today?', kind: 'mood' })).toEqual({
    question: 'How are you feeling today?', kind: 'mood',
    choices: [{ key: 'great', label: 'Doing great 👍' }, { key: 'okay', label: 'Okay' }, { key: 'not_great', label: 'Not so good' }],
    low: null, high: null, answered: false, answerText: null
  });
  expect(contentState({ questionText: 'Pain today?', kind: 'scale', low: 'None', high: 'Worst' }, { answered: true, answerText: '3/10' }))
    .toMatchObject({ choices: [], low: 'None', high: 'Worst', answered: true, answerText: '3/10' });
});

test('a question goes on the Lock Screen when the phone registered for it, and not otherwise', async () => {
  await activePlan();
  await care.runDue({ now: T_0835_NY });
  expect(liveActivityPush.sendLiveActivity).not.toHaveBeenCalled();

  await care.registerLiveStartToken(PARENT, { token: 'start-tok', fcmToken: 'fcm-1' });
  await care.runDue({ now: T_1305_NY });
  expect(liveActivityPush.sendLiveActivity).toHaveBeenCalledWith(expect.objectContaining({
    event: 'start', token: 'start-tok', fcmToken: 'fcm-1', attributesType: ATTRIBUTES_TYPE,
    attributes: { askId: `${PLAN}_2026-09-19_1300`, planId: PLAN, fromName: 'Wes' },
    state: expect.objectContaining({ answered: false })
  }));
  // The normal question push still goes out too
  expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({ title: 'Wes asks' }));
});

test('answering takes it down showing the answer; only the parent can attach a display token', async () => {
  await activePlan();
  await care.registerLiveStartToken(PARENT, { token: 'start-tok', fcmToken: 'fcm-1' });
  await care.runDue({ now: T_0835_NY });
  const askId = `${PLAN}_2026-09-19_0830`;
  expect(await care.registerAskLiveToken(CHILD, askId, { token: 'x', fcmToken: 'y' })).toEqual({ registered: false });
  expect(await care.registerAskLiveToken(PARENT, askId, { token: 'act-tok', fcmToken: 'fcm-1' })).toEqual({ registered: true });
  liveActivityPush.sendLiveActivity.mockClear();

  await care.answerAsk({ userId: PARENT, askId, answer: 'great' });
  expect(liveActivityPush.sendLiveActivity).toHaveBeenCalledWith(expect.objectContaining({
    event: 'end', token: 'act-tok', state: expect.objectContaining({ answered: true, answerText: 'Doing great 👍' })
  }));
  await new Promise((r) => setImmediate(r));
  expect(asks().get(askId).liveToken).toBeNull();
});

test('the next question replaces an unanswered one on the Lock Screen', async () => {
  await activePlan();
  await care.registerLiveStartToken(PARENT, { token: 'start-tok', fcmToken: 'fcm-1' });
  await care.runDue({ now: T_0835_NY });
  await care.registerAskLiveToken(PARENT, `${PLAN}_2026-09-19_0830`, { token: 'morning-tok', fcmToken: 'fcm-1' });
  liveActivityPush.sendLiveActivity.mockClear();

  await care.runDue({ now: T_1305_NY });
  const calls = liveActivityPush.sendLiveActivity.mock.calls.map(([p]) => [p.event, p.token]);
  expect(calls).toEqual([['end', 'morning-tok'], ['start', 'start-tok']]);
});

test('a dead start token is forgotten', async () => {
  await activePlan();
  await care.registerLiveStartToken(PARENT, { token: 'old', fcmToken: 'fcm-1' });
  liveActivityPush.sendLiveActivity.mockImplementation(async () => 'gone');
  await care.runDue({ now: T_0835_NY });
  expect(mockDb.rows('careLiveStartTokens').has(PARENT)).toBe(false);
});

test('an hour unanswered with no Lock Screen display: asked once more, once', async () => {
  await activePlan();
  await care.runDue({ now: T_0835_NY });
  notificationService.sendToUser.mockClear();
  // 30 minutes on: too soon
  await care.runDue({ now: new Date(T_0835_NY.getTime() + minutes(30)) });
  expect(notificationService.sendToUser).not.toHaveBeenCalled();
  // An hour on: the question again, buttons and all
  await care.runDue({ now: new Date(T_0835_NY.getTime() + minutes(65)) });
  expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
  expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
    type: 'care_ask', title: 'Still wondering · Wes asks', body: 'How are you feeling today?',
    data: expect.objectContaining({ askId: `${PLAN}_2026-09-19_0830`, reminder: '1' })
  }));
  // Never twice
  await care.runDue({ now: new Date(T_0835_NY.getTime() + minutes(80)) });
  expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
});

test('no reminder when the question is already on the Lock Screen', async () => {
  await activePlan();
  await care.runDue({ now: T_0835_NY });
  await care.registerAskLiveToken(PARENT, `${PLAN}_2026-09-19_0830`, { token: 'act', fcmToken: 'fcm-1' });
  notificationService.sendToUser.mockClear();
  await care.runDue({ now: new Date(T_0835_NY.getTime() + minutes(65)) });
  expect(notificationService.sendToUser).not.toHaveBeenCalled();
});
