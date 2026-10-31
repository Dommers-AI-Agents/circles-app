// One heart for a feed group row: every activity in it gets the reaction,
// the owner gets ONE notification, and un-hearting clears them all.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../piggyBankService', () => ({ credit: jest.fn(async () => ({ credited: true, amount: 0.05 })) }));
jest.mock('../funnelService', () => ({ stampFunnelMilestone: jest.fn() }));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const piggy = require('../piggyBankService');
const { reactToGroup, groupReactionBody } = require('../activityGroupReactionService');

const push = { sendToUser: jest.fn(async () => {}) };
const sse = { notifyUser: jest.fn() };
const deps = { notificationService: push, sseService: sse };

beforeEach(() => {
  for (const c of [COLLECTIONS.ACTIVITIES, COLLECTIONS.ACTIVITY_REACTIONS, COLLECTIONS.NOTIFICATIONS, COLLECTIONS.USERS]) mockDb.rows(c).clear();
  jest.clearAllMocks();
  mockDb.collection(COLLECTIONS.USERS).doc('me').set({ displayName: 'Sam' });
  for (const id of ['a1', 'a2', 'a3']) mockDb.collection(COLLECTIONS.ACTIVITIES).doc(id).set({ actorId: 'wes', reactionCount: 0 });
});

const reactionCount = (id) => mockDb.rows(COLLECTIONS.ACTIVITIES).get(id).reactionCount;

test('hearting a group reacts to every activity with one notification and one nickel', async () => {
  const out = await reactToGroup({ userId: 'me', activityIds: ['a1', 'a2', 'a3'], emoji: '👍' }, deps);
  expect(out.results.map((r) => r.emoji)).toEqual(['👍', '👍', '👍']);
  expect(['a1', 'a2', 'a3'].map(reactionCount)).toEqual([1, 1, 1]);
  expect(mockDb.rows(COLLECTIONS.NOTIFICATIONS).size).toBe(1);
  expect(push.sendToUser).toHaveBeenCalledTimes(1);
  expect(push.sendToUser.mock.calls[0][1].body).toBe('Sam reacted 👍 to 3 of your activities');
  expect(piggy.credit).toHaveBeenCalledTimes(1);
});

test('only the activities not yet reacted to count, notify and add to totals', async () => {
  await reactToGroup({ userId: 'me', activityIds: ['a1'], emoji: '👍' }, deps);
  jest.clearAllMocks();
  await reactToGroup({ userId: 'me', activityIds: ['a1', 'a2'], emoji: '❤️' }, deps);
  expect(reactionCount('a1')).toBe(1);
  expect(reactionCount('a2')).toBe(1);
  expect(mockDb.rows(COLLECTIONS.ACTIVITY_REACTIONS).get('a1_me').emoji).toBe('❤️');
  expect(push.sendToUser.mock.calls[0][1].body).toBe('Sam reacted ❤️ to your activity');
});

test('un-hearting the group clears every reaction and sends nothing', async () => {
  await reactToGroup({ userId: 'me', activityIds: ['a1', 'a2'], emoji: '👍' }, deps);
  jest.clearAllMocks();
  const out = await reactToGroup({ userId: 'me', activityIds: ['a1', 'a2', 'a3'], remove: true }, deps);
  expect(out.results.every((r) => r.emoji === null)).toBe(true);
  expect(['a1', 'a2', 'a3'].map(reactionCount)).toEqual([0, 0, 0]);
  expect(mockDb.rows(COLLECTIONS.ACTIVITY_REACTIONS).size).toBe(0);
  expect(push.sendToUser).not.toHaveBeenCalled();
});

test('your own group: reactions land, nobody is notified, no coins', async () => {
  mockDb.collection(COLLECTIONS.USERS).doc('wes').set({ displayName: 'Wes' });
  await reactToGroup({ userId: 'wes', activityIds: ['a1', 'a2'], emoji: '👍' }, deps);
  expect(reactionCount('a1')).toBe(1);
  expect(push.sendToUser).not.toHaveBeenCalled();
  expect(piggy.credit).not.toHaveBeenCalled();
});

test('refuses mixed people, bad emoji, empty and oversized lists; skips deleted activities', async () => {
  mockDb.collection(COLLECTIONS.ACTIVITIES).doc('b1').set({ actorId: 'someone' });
  await expect(reactToGroup({ userId: 'me', activityIds: ['a1', 'b1'], emoji: '👍' }, deps)).rejects.toMatchObject({ code: 'mixed_group' });
  await expect(reactToGroup({ userId: 'me', activityIds: ['a1'], emoji: '💩' }, deps)).rejects.toMatchObject({ code: 'invalid_reaction' });
  await expect(reactToGroup({ userId: 'me', activityIds: [], emoji: '👍' }, deps)).rejects.toMatchObject({ status: 400 });
  await expect(reactToGroup({ userId: 'me', activityIds: Array.from({ length: 51 }, (_, i) => `x${i}`), emoji: '👍' }, deps)).rejects.toMatchObject({ code: 'too_many_activities' });
  const out = await reactToGroup({ userId: 'me', activityIds: ['a1', 'gone'], emoji: '👍' }, deps);
  expect(out.results.map((r) => r.activityId)).toEqual(['a1']);
});

test('notification wording', () => {
  expect(groupReactionBody('Sam', '👍', 1)).toBe('Sam reacted 👍 to your activity');
  expect(groupReactionBody('Sam', '🎉', 4)).toBe('Sam reacted 🎉 to 4 of your activities');
});
