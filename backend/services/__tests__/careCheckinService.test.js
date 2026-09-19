// "How Are You?" check-ins: invite → accept → questions at the parent's local
// times → one-tap answers → silence alerts that never fire for a push the
// phone didn't get. Push is mocked and asserted; Firestore is the fake.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
const mockConnections = new Map();
jest.mock('../connectionMap', () => ({ buildConnectionMap: jest.fn(async () => mockConnections) }));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn(async () => ({ success: true })) }));

const notificationService = require('../notificationService');
const care = require('../careCheckinService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const CHILD = 'child_1';
const PARENT = 'parent_1';
const PLAN = `${CHILD}_${PARENT}`;
const SIBLING = 'child_2';

const plans = () => mockDb.rows(COLLECTIONS.CARE_PLANS);
const asks = () => mockDb.rows(COLLECTIONS.CARE_ASKS);

// 2026-09-19 12:35 UTC = 08:35 in New York, 05:35 in Los Angeles
const T_0835_NY = new Date('2026-09-19T12:35:00Z');

async function seedUsers() {
  await mockDb.collection(COLLECTIONS.USERS).doc(CHILD).set({ displayName: 'Wes' });
  await mockDb.collection(COLLECTIONS.USERS).doc(PARENT).set({ displayName: 'Mom', notificationPreferences: { timezone: 'America/New_York' } });
  mockConnections.set(PARENT, { status: 'accepted' });
}

async function activePlan(overrides = {}) {
  await seedUsers();
  await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['08:30', '13:00', '19:00'], questions: [] });
  await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: true, timezone: 'America/New_York' });
  if (Object.keys(overrides).length) await plans().set(PLAN, { ...plans().get(PLAN), ...overrides });
  notificationService.sendToUser.mockClear();
}

beforeEach(() => {
  plans().clear();
  asks().clear();
  mockDb.rows(COLLECTIONS.USERS).clear();
  mockConnections.clear();
  notificationService.sendToUser.mockClear();
  notificationService.sendToUser.mockImplementation(async () => ({ success: true }));
});

describe('setting up', () => {
  test('creating a plan needs an accepted connection and invites the parent', async () => {
    await seedUsers();
    mockConnections.set(PARENT, { status: 'pending' });
    await expect(care.createPlan({ ownerId: CHILD, parentId: PARENT })).rejects.toMatchObject({ code: 'not_connected' });

    mockConnections.set(PARENT, { status: 'accepted' });
    const plan = await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['9:00', '08:30', '08:30', '25:00'], questions: ['Did you sleep?', '  ', 'Did you sleep?'] });
    expect(plan.status).toBe('invited');
    expect(plan.parentName).toBe('Mom');
    expect(plan.times).toEqual(['08:30']); // invalid and duplicate times dropped
    expect(plan.questions.map((q) => q.text)).toEqual(['Did you sleep?', 'Did you sleep?']);
    expect(plan.timezone).toBe('America/New_York'); // from the parent's preferences
    expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
      type: 'care_invite', title: 'Wes wants to check in on you', data: expect.objectContaining({ type: 'care_invite', planId: PLAN })
    }));
    await expect(care.createPlan({ ownerId: CHILD, parentId: PARENT })).rejects.toMatchObject({ code: 'exists' });
  });

  test('only the parent can accept; accepting activates, stores the device timezone and tells the child', async () => {
    await seedUsers();
    await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['08:30', '19:00'] });
    await expect(care.respondToInvite({ userId: CHILD, planId: PLAN, accept: true })).rejects.toMatchObject({ code: 'not_parent' });
    const plan = await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: true, timezone: 'America/Los_Angeles' });
    expect(plan.status).toBe('active');
    expect(plan.timezone).toBe('America/Los_Angeles');
    expect(plan.role).toBe('parent');
    expect(notificationService.sendToUser).toHaveBeenLastCalledWith(CHILD, expect.objectContaining({ type: 'care_accepted', title: 'Mom said yes to check-ins' }));
  });

  test('declining and ending are honored, and nothing is asked until accepted', async () => {
    await seedUsers();
    await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['08:30'] });
    await expect(care.updatePlan({ userId: CHILD, planId: PLAN, status: 'active' })).rejects.toMatchObject({ code: 'not_accepted' });
    expect((await care.runDue({ now: T_0835_NY })).asked).toBe(0);
    const declined = await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: false });
    expect(declined.status).toBe('declined');
    await care.endPlan({ userId: CHILD, planId: PLAN });
    expect((await care.listPlans(CHILD)).asOwner).toEqual([]);
  });
});

describe('asking', () => {
  test('a slot fires once inside its 15-minute window, in the parent\'s zone, with a Lock Screen category payload', async () => {
    await activePlan();
    const first = await care.runDue({ now: T_0835_NY });
    expect(first.asked).toBe(1);
    const [askId, ask] = [...asks().entries()][0];
    expect(askId).toBe(`${PLAN}_2026-09-19_0830`);
    expect(ask).toMatchObject({ status: 'open', slot: '08:30', questionText: 'How are you feeling today?', pushDelivered: true });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
      type: 'care_ask', title: 'Wes asks', body: 'How are you feeling today?',
      data: expect.objectContaining({ type: 'care_ask', askId, planId: PLAN })
    }));
    // The same window again (a retried run) does not double-ask.
    expect((await care.runDue({ now: new Date(T_0835_NY.getTime() + 5 * 60000) })).asked).toBe(0);
    // Outside the window, nothing. 13:00 NY is 17:00 UTC.
    expect((await care.runDue({ now: new Date('2026-09-19T16:50:00Z') })).asked).toBe(0);
    expect((await care.runDue({ now: new Date('2026-09-19T17:10:00Z') })).asked).toBe(1);
    expect(asks().size).toBe(2);
  });

  test('the parent\'s timezone decides the slot, not the server clock', async () => {
    await activePlan({ timezone: 'America/Los_Angeles' });
    expect((await care.runDue({ now: T_0835_NY })).asked).toBe(0); // 05:35 in LA
    expect((await care.runDue({ now: new Date('2026-09-19T15:40:00Z') })).asked).toBe(1); // 08:40 in LA
  });

  test('questions rotate through the child\'s own list and survive edits', async () => {
    await activePlan();
    await care.updatePlan({ userId: CHILD, planId: PLAN, questions: ['Sleep ok?', 'Eat yet?'] });
    await care.runDue({ now: T_0835_NY });
    await care.runDue({ now: new Date('2026-09-19T17:05:00Z') });
    await care.runDue({ now: new Date('2026-09-19T23:05:00Z') });
    const texts = [...asks().values()].sort((a, b) => (a.askedAt < b.askedAt ? -1 : 1)).map((a) => a.questionText);
    expect(texts).toEqual(['Sleep ok?', 'Eat yet?', 'Sleep ok?']);
    // Editing the list later doesn't rewrite what was already asked.
    await care.updatePlan({ userId: CHILD, planId: PLAN, questions: ['Something new?'] });
    expect([...asks().values()].every((a) => a.questionText !== 'Something new?')).toBe(true);
  });

  test('paused plans are silent', async () => {
    await activePlan();
    await care.updatePlan({ userId: CHILD, planId: PLAN, status: 'paused' });
    expect((await care.runDue({ now: T_0835_NY })).asked).toBe(0);
  });
});

describe('answering', () => {
  test('the parent answers once; the child gets the answer and the note', async () => {
    await activePlan();
    await care.runDue({ now: T_0835_NY });
    const askId = [...asks().keys()][0];
    notificationService.sendToUser.mockClear();
    await expect(care.answerAsk({ userId: CHILD, askId, answer: 'great' })).rejects.toMatchObject({ code: 'not_parent' });
    await expect(care.answerAsk({ userId: PARENT, askId, answer: 'meh' })).rejects.toMatchObject({ code: 'bad_answer' });
    const ask = await care.answerAsk({ userId: PARENT, askId, answer: 'great', note: 'Slept like a log' });
    expect(ask).toMatchObject({ status: 'answered', answer: 'great', answerText: 'Doing great 👍', note: 'Slept like a log' });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({
      type: 'care_answer', title: 'Mom: Doing great 👍', body: '“How are you feeling today?” — "Slept like a log"'
    }));
    // A second tap is a no-op, not a second push.
    notificationService.sendToUser.mockClear();
    const again = await care.answerAsk({ userId: PARENT, askId, answer: 'okay' });
    expect(again.answer).toBe('great');
    expect(notificationService.sendToUser).not.toHaveBeenCalled();
    // Answered asks never raise a silence alert.
    const sweep = await care.runDue({ now: new Date(T_0835_NY.getTime() + 4 * 3600 * 1000) });
    expect(sweep.silence).toBe(0);
    const plan = (await care.listPlans(CHILD)).asOwner[0];
    expect(plan.lastAnswer.answerText).toBe('Doing great 👍');
    expect(plan.openAsk).toBeNull();
  });
});

describe('silence', () => {
  test('unanswered for three hours → the child is told, once', async () => {
    await activePlan();
    await care.runDue({ now: T_0835_NY });
    notificationService.sendToUser.mockClear();
    expect((await care.runDue({ now: new Date(T_0835_NY.getTime() + 2 * 3600 * 1000) })).silence).toBe(0);
    const later = new Date(T_0835_NY.getTime() + 3 * 3600 * 1000 + 60000);
    expect((await care.runDue({ now: later })).silence).toBe(1);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({
      type: 'care_silence', title: "Mom hasn't answered", body: '“How are you feeling today?” went out at 8:30 AM their time and hasn\'t been answered.'
    }));
    expect([...asks().values()][0]).toMatchObject({ status: 'missed', alertKind: 'silence' });
    expect((await care.runDue({ now: new Date(later.getTime() + 3600 * 1000) })).silence).toBe(0);
  });

  test('a push the phone never got is reported as undelivered, not as silence', async () => {
    await activePlan();
    notificationService.sendToUser.mockImplementation(async () => ({ success: false, error: 'No device tokens' }));
    await care.runDue({ now: T_0835_NY });
    expect([...asks().values()][0]).toMatchObject({ pushDelivered: false, pushError: 'No device tokens' });
    notificationService.sendToUser.mockClear();
    notificationService.sendToUser.mockImplementation(async () => ({ success: true }));
    const result = await care.runDue({ now: new Date(T_0835_NY.getTime() + 3 * 3600 * 1000 + 60000) });
    expect(result).toMatchObject({ silence: 0, undelivered: 1 });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({
      type: 'care_silence', title: "Mom's phone isn't getting check-ins", data: expect.objectContaining({ kind: 'undelivered' })
    }));
    expect([...asks().values()][0]).toMatchObject({ status: 'missed', alertKind: 'undelivered' });
  });
});

describe('reads', () => {
  test('listPlans splits roles and embeds the open question for the parent', async () => {
    await activePlan();
    await care.runDue({ now: T_0835_NY });
    const mine = await care.listPlans(PARENT);
    expect(mine.asOwner).toEqual([]);
    expect(mine.asParent[0]).toMatchObject({ role: 'parent', ownerName: 'Wes', openAsk: expect.objectContaining({ questionText: 'How are you feeling today?' }) });
    expect(mine.asParent[0].answers).toEqual({ great: 'Doing great 👍', okay: 'Okay', not_great: 'Not so good' });
    const history = await care.listAsks({ userId: CHILD, planId: PLAN });
    expect(history).toHaveLength(1);
    await expect(care.listAsks({ userId: 'stranger', planId: PLAN })).rejects.toMatchObject({ code: 'not_yours' });
  });

  test('helpers', () => {
    expect(care.friendlyTime('08:30')).toBe('8:30 AM');
    expect(care.friendlyTime('13:05')).toBe('1:05 PM');
    expect(care.friendlyTime('00:00')).toBe('12:00 AM');
    expect(care.localDateKey('America/New_York', new Date('2026-09-20T03:30:00Z'))).toBe('2026-09-19');
    expect(care.localDateKey('Asia/Tokyo', new Date('2026-09-20T03:30:00Z'))).toBe('2026-09-20');
  });
});

describe('siblings joining (watchers)', () => {
  const seedSibling = async () => {
    await mockDb.collection(COLLECTIONS.USERS).doc(SIBLING).set({ displayName: 'Kate' });
    mockConnections.set(SIBLING, { status: 'accepted' });
  };

  test('a sibling asks to join; the PARENT decides, not the owner', async () => {
    await activePlan();
    await seedSibling();

    const pending = await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    expect(pending.watchers).toEqual([expect.objectContaining({ userId: SIBLING, status: 'invited' })]);
    // The parent is the one asked.
    expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
      type: 'care_watcher_request'
    }));
    // ...and until they say yes, the sibling sees nothing.
    expect(plans().get(PLAN).watcherIds || []).toEqual([]);
    await expect(care.listAsks({ userId: SIBLING, planId: PLAN })).rejects.toMatchObject({ code: 'not_yours' });

    // The owner cannot wave their sibling through on the parent's behalf.
    await expect(care.respondToWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING, accept: true }))
      .rejects.toMatchObject({ code: 'not_parent' });

    const accepted = await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true });
    expect(accepted.watchers[0]).toMatchObject({ userId: SIBLING, status: 'active' });
    expect(plans().get(PLAN).watcherIds).toEqual([SIBLING]);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(SIBLING, expect.objectContaining({
      type: 'care_watcher_accepted'
    }));
    await expect(care.listAsks({ userId: SIBLING, planId: PLAN })).resolves.toBeDefined();
  });

  test('a declined sibling is dropped, not left pending forever', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    const after = await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: false });
    expect(after.watchers).toEqual([]);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(SIBLING, expect.objectContaining({
      type: 'care_watcher_declined'
    }));
  });

  test('the owner may invite; anyone else may only ask for themselves', async () => {
    await activePlan();
    await seedSibling();
    await expect(care.requestWatcher({ userId: SIBLING, planId: PLAN, watcherId: 'someone_else' }))
      .rejects.toMatchObject({ code: 'not_owner' });
    const invited = await care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING });
    expect(invited.watchers[0]).toMatchObject({ userId: SIBLING, status: 'invited', invitedBy: CHILD });
  });

  test('a watcher must be connected to the PARENT, not just to the sibling', async () => {
    await activePlan();
    await mockDb.collection(COLLECTIONS.USERS).doc(SIBLING).set({ displayName: 'Kate' });
    mockConnections.delete(SIBLING);          // connected to the child, not to Mom
    await expect(care.requestWatcher({ userId: SIBLING, planId: PLAN }))
      .rejects.toMatchObject({ code: 'not_connected' });
  });

  test('duplicate requests are refused, and the owner cannot join their own plan', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await expect(care.requestWatcher({ userId: SIBLING, planId: PLAN })).rejects.toMatchObject({ code: 'already_watching' });
    await expect(care.requestWatcher({ userId: CHILD, planId: PLAN })).rejects.toMatchObject({ code: 'already_owner' });
  });

  test('answers and silence reach every accepted sibling, not just the owner', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true });

    await care.runDue({ now: T_0835_NY });
    const askId = [...asks().keys()][0];
    notificationService.sendToUser.mockClear();
    await care.answerAsk({ userId: PARENT, askId, answer: 'okay' });
    const told = notificationService.sendToUser.mock.calls
      .filter(([, payload]) => payload.type === 'care_answer').map(([to]) => to);
    expect(told).toEqual(expect.arrayContaining([CHILD, SIBLING]));

    // ...and the silence, which is the whole reason a sibling joins.
    notificationService.sendToUser.mockClear();
    await asks().set(askId, { ...asks().get(askId), status: 'open', answeredAt: null, alertedAt: null, dueBy: '2026-09-19T00:00:00Z' });
    await care.runDue({ now: new Date('2026-09-19T20:00:00Z') });
    const alerted = notificationService.sendToUser.mock.calls
      .filter(([, payload]) => payload.type === 'care_silence').map(([to]) => to);
    expect(alerted).toEqual(expect.arrayContaining([CHILD, SIBLING]));
  });

  test('a second child is pointed at the existing plan instead of asking Mom twice', async () => {
    await activePlan();
    await seedSibling();
    await expect(care.createPlan({ ownerId: SIBLING, parentId: PARENT }))
      .rejects.toMatchObject({ code: 'plan_exists', details: { planId: PLAN } });
  });

  test('joining by naming the parent finds the plan a sibling already made', async () => {
    await activePlan();
    await seedSibling();
    const joined = await care.requestWatcherForParent({ userId: SIBLING, parentId: PARENT });
    expect(joined.planId).toBe(PLAN);
    expect(joined.watchers[0]).toMatchObject({ userId: SIBLING, status: 'invited' });
    // Nobody checking in on them yet → set one up instead of joining nothing.
    await expect(care.requestWatcherForParent({ userId: SIBLING, parentId: 'stranger' }))
      .rejects.toMatchObject({ code: 'no_plan' });
  });

  test('a watcher sees the plan but never changes the schedule', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true });

    const listed = await care.listPlans(SIBLING);
    expect(listed.asWatcher.map((p) => p.planId)).toEqual([PLAN]);
    expect(listed.asOwner).toEqual([]);
    await expect(care.updatePlan({ userId: SIBLING, planId: PLAN, times: ['09:00'] }))
      .rejects.toMatchObject({ code: 'not_owner' });
  });

  test('a watcher can leave, and the parent can remove one', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true });

    expect((await care.removeWatcher({ userId: SIBLING, planId: PLAN, watcherId: SIBLING })).watchers).toEqual([]);
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true });
    expect((await care.removeWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING })).watchers).toEqual([]);
    expect(plans().get(PLAN).watcherIds).toEqual([]);
  });
});
