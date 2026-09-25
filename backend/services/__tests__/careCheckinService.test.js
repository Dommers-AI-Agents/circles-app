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
// The recording variant is a bell row PLUS the push, so it delegates to
// sendToUser here: every "was the push sent" assertion below still holds.
jest.mock('../notificationService', () => {
  const sendToUser = jest.fn(async () => ({ success: true }));
  return { sendToUser, sendToUserWithRecord: jest.fn((userId, payload) => sendToUser(userId, payload)) };
});

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
    expect(plan.questions.map((q) => [q.text, q.kind])).toEqual([['Did you sleep?', 'yesno']]); // duplicates dropped; a typed question is a yes/no
    expect(plan.profile).toBeNull(); // the care questionnaire hasn't been done
    expect(plan.rotation.map((q) => q.id)).toContain('mood_morning');
    expect(plan.rotation.map((q) => q.id)).not.toContain('pt_week'); // no profile → no PT
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
    // Invitations and answers are things people go back to look for: bell row + push.
    expect(notificationService.sendToUserWithRecord).toHaveBeenLastCalledWith(CHILD, expect.objectContaining({ type: 'care_accepted' }));
  });

  test('the owner can send the invitation again, not too often, and hears whether the phone got it', async () => {
    await seedUsers();
    await care.createPlan({ ownerId: CHILD, parentId: PARENT, times: ['08:30'] });
    notificationService.sendToUser.mockClear();
    const created = Date.parse(plans().get(PLAN).createdAt);

    await expect(care.resendInvite({ userId: PARENT, planId: PLAN })).rejects.toMatchObject({ code: 'not_owner' });
    // Right after creating it: the first push just went out.
    await expect(care.resendInvite({ userId: CHILD, planId: PLAN, now: new Date(created + 60000) })).rejects.toMatchObject({ code: 'too_soon' });
    expect(notificationService.sendToUser).not.toHaveBeenCalled();

    const later = new Date(created + 11 * 60000);
    const sent = await care.resendInvite({ userId: CHILD, planId: PLAN, now: later });
    expect(sent.delivered).toBe(true);
    expect(sent.plan.status).toBe('invited');
    expect(sent.plan.lastInvitedAt).toBe(later.toISOString());
    expect(plans().get(PLAN).inviteCount).toBe(2);
    expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
      type: 'care_invite', title: 'Wes wants to check in on you', data: expect.objectContaining({ type: 'care_invite', planId: PLAN })
    }));

    // Inside the cooldown again, measured from the resend.
    await expect(care.resendInvite({ userId: CHILD, planId: PLAN, now: new Date(later.getTime() + 60000) })).rejects.toMatchObject({ code: 'too_soon' });

    // A push the phone never got is reported, not hidden.
    notificationService.sendToUser.mockImplementation(async () => ({ success: false, error: 'No device tokens' }));
    const missed = await care.resendInvite({ userId: CHILD, planId: PLAN, now: new Date(later.getTime() + 11 * 60000) });
    expect(missed.delivered).toBe(false);

    // Once accepted or declined there is nothing to resend.
    await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: false });
    await expect(care.resendInvite({ userId: CHILD, planId: PLAN, now: new Date(later.getTime() + 30 * 60000) })).rejects.toMatchObject({ code: 'not_invited' });
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

  test('a parent on an older app only gets mood questions, one per time of day', async () => {
    await activePlan();
    await care.updatePlan({ userId: CHILD, planId: PLAN, questions: ['Sleep ok?', 'Eat yet?'] }); // yes/no kind: no buttons on an old build
    await care.runDue({ now: T_0835_NY });
    await care.runDue({ now: new Date('2026-09-19T17:05:00Z') });
    await care.runDue({ now: new Date('2026-09-19T23:05:00Z') });
    const sent = [...asks().values()].sort((a, b) => (a.askedAt < b.askedAt ? -1 : 1));
    expect(sent.map((a) => a.questionText)).toEqual(['How are you feeling today?', 'How is your afternoon going?', 'How was your day?']);
    expect(sent.every((a) => a.kind === 'mood')).toBe(true);
    expect(notificationService.sendToUser.mock.calls.filter(([to]) => to === PARENT).every(([, p]) => p.type === 'care_ask')).toBe(true);
    expect(plans().get(PLAN).parentCanAnswerRich).toBe(false);
    // Editing the list later doesn't rewrite what was already asked.
    await care.updatePlan({ userId: CHILD, planId: PLAN, questions: ['Something new?'] });
    expect([...asks().values()].every((a) => a.questionText !== 'Something new?')).toBe(true);
  });

  test('a parent on a new app gets the kinds, the profile picks the questions, and each push type matches its kind', async () => {
    await activePlan();
    await mockDb.collection(COLLECTIONS.USERS).doc(PARENT).set({ displayName: 'Mom', deviceTokens: [{ token: 't', platform: 'ios', appVersion: '1.3.3', appBuild: 6 }] });
    await care.updatePlan({ userId: CHILD, planId: PLAN, profile: { takesMeds: true, hasPT: true, chronicPain: true } });
    // Friday 2026-09-25: the PT week question is due, and takes the day's last evening slot.
    await care.runDue({ now: new Date('2026-09-25T12:35:00Z') }); // 08:35 NY
    await care.runDue({ now: new Date('2026-09-25T17:05:00Z') }); // 13:05 NY
    await care.runDue({ now: new Date('2026-09-25T23:05:00Z') }); // 19:05 NY
    const sent = [...asks().values()].sort((a, b) => (a.askedAt < b.askedAt ? -1 : 1));
    expect(sent.map((a) => a.questionId)).toEqual(['meds_today', 'pain', 'pt_week']);
    expect(sent.map((a) => a.kind)).toEqual(['done', 'scale', 'yesno']);
    expect(sent[1]).toMatchObject({ short: 'Pain', low: 'No pain', high: 'Worst pain', alertRule: { min: 7 } });
    const types = notificationService.sendToUser.mock.calls.filter(([to]) => to === PARENT).map(([, p]) => p.type);
    expect(types).toEqual(['care_ask_done', 'care_ask_scale', 'care_ask_yesno']);
    expect(notificationService.sendToUser.mock.calls.find(([, p]) => p.type === 'care_ask_scale')[1].data).toMatchObject({ kind: 'scale' });
    expect(plans().get(PLAN).parentCanAnswerRich).toBe(true);
    // The next day, PT waits for Friday.
    await care.runDue({ now: new Date('2026-09-26T17:05:00Z') });
    const saturday = [...asks().values()].find((a) => a.dateKey === '2026-09-26');
    expect(saturday.questionId).not.toBe('pt_week');
    // Muting a bank question keeps it out; the owner sees the rotation with the reason.
    const plan = await care.updatePlan({ userId: CHILD, planId: PLAN, mutedQuestionIds: ['pain', 'not_a_question'] });
    expect(plan.mutedQuestionIds).toEqual(['pain']);
    expect(plan.rotation.find((q) => q.id === 'pain')).toMatchObject({ muted: true, source: 'bank', cadence: 'Daily', kind: 'scale' });
    expect(plan.rotation.find((q) => q.id === 'pt_week')).toMatchObject({ cadence: 'Weekly · Fridays', requires: 'hasPT' });
    expect(plan.rotation.find((q) => q.id === 'falls')).toBeUndefined();
    expect(plan.profile).toEqual(expect.objectContaining({ takesMeds: true, hasPT: true, chronicPain: true, livesAlone: false }));
    expect(plan.profileFields.length).toBeGreaterThan(5);
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

describe('answering by kind', () => {
  async function richPlan(profile) {
    await activePlan();
    await mockDb.collection(COLLECTIONS.USERS).doc(PARENT).set({ displayName: 'Mom', deviceTokens: [{ token: 't', platform: 'ios', appVersion: '1.3.4' }] });
    await care.updatePlan({ userId: CHILD, planId: PLAN, profile });
    notificationService.sendToUser.mockClear();
  }

  test('a 0–10 question takes a number, words it, and a bad day is a heads-up to the family', async () => {
    await richPlan({ chronicPain: true });
    await care.runDue({ now: new Date('2026-09-21T17:05:00Z') }); // Monday 13:05 NY: pain (daily, weight) beats the rest
    const [askId, ask] = [...asks().entries()].find(([, a]) => a.questionId === 'pain');
    expect(ask.kind).toBe('scale');
    notificationService.sendToUser.mockClear();
    await expect(care.answerAsk({ userId: PARENT, askId, value: 11 })).rejects.toMatchObject({ code: 'bad_answer', message: 'Answer with a number from 0 to 10.' });
    await expect(care.answerAsk({ userId: PARENT, askId, answer: 'great' })).rejects.toMatchObject({ code: 'bad_answer' });
    const answered = await care.answerAsk({ userId: PARENT, askId, value: '8', note: 'my hip' });
    expect(answered).toMatchObject({ kind: 'scale', answer: null, answerValue: '8', answerScore: 8, answerText: 'Pain 8/10', alert: true, low: 'No pain', high: 'Worst pain' });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({
      type: 'care_answer', title: 'Heads up · Mom: Pain 8/10', body: '“How much pain are you in today?” — "my hip"',
      data: expect.objectContaining({ kind: 'scale', answer: '8', alert: '1' })
    }));
  });

  test('a did-you question takes yes / not yet / no, and "no" to medicine is a heads-up', async () => {
    await richPlan({ takesMeds: true });
    await care.runDue({ now: new Date('2026-09-22T12:35:00Z') }); // Tuesday 08:35 NY
    const [askId, ask] = [...asks().entries()].find(([, a]) => a.questionId === 'meds_today');
    expect(ask.kind).toBe('done');
    await expect(care.answerAsk({ userId: PARENT, askId, answer: 'great' })).rejects.toMatchObject({ code: 'bad_answer', message: 'Answer must be yes, not_yet or no.' });
    const answered = await care.answerAsk({ userId: PARENT, askId, answer: 'no' });
    expect(answered).toMatchObject({ kind: 'done', answer: 'no', answerValue: 'no', answerText: 'No', alert: true });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({ title: 'Heads up · Mom: No' }));
    // "Yes" on a later day is a plain answer. (Morning slots are shared with sleep and the rest, so find the next one.)
    let next = null;
    for (let day = 23; day <= 27 && !next; day += 1) {
      await care.runDue({ now: new Date(`2026-09-${day}T12:35:00Z`) });
      next = [...asks().entries()].find(([, a]) => a.questionId === 'meds_today' && a.dateKey === `2026-09-${day}`);
    }
    const [askId2] = next;
    notificationService.sendToUser.mockClear();
    expect(await care.answerAsk({ userId: PARENT, askId: askId2, answer: 'yes' })).toMatchObject({ answerText: 'Yes', alert: false });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({ title: 'Mom: Yes' }));
  });

  test('a typed answer is kept as words; blank is refused', async () => {
    await richPlan({ needsRides: true });
    await care.runDue({ now: new Date('2026-09-23T23:05:00Z') }); // Wednesday 19:05 NY: rides is pinned to Wednesdays
    const [askId, ask] = [...asks().entries()].find(([, a]) => a.questionId === 'rides');
    expect(ask.kind).toBe('text');
    await expect(care.answerAsk({ userId: PARENT, askId, value: '   ' })).rejects.toMatchObject({ code: 'bad_answer', message: 'Type a few words.' });
    const answered = await care.answerAsk({ userId: PARENT, askId, value: 'Eye doctor Thursday  at 2' });
    expect(answered).toMatchObject({ kind: 'text', answer: null, answerValue: 'Eye doctor Thursday at 2', answerText: 'Eye doctor Thursday at 2', alert: false });
    const history = await care.listAsks({ userId: CHILD, planId: PLAN });
    expect(history[0]).toMatchObject({ kind: 'text', answerText: 'Eye doctor Thursday at 2' });
  });

  test('the parent answering from a new build marks the plan as able to take rich questions', async () => {
    await activePlan();
    await care.runDue({ now: T_0835_NY });
    const askId = [...asks().keys()][0];
    await care.answerAsk({ userId: PARENT, askId, answer: 'okay', client: { version: '1.3.3', build: 6 } });
    expect(plans().get(PLAN).parentCanAnswerRich).toBe(true);
    await care.respondToInvite({ userId: PARENT, planId: PLAN, accept: true, client: { version: '1.3.3', build: null } });
    expect(plans().get(PLAN).parentCanAnswerRich).toBe(true); // never un-set by an older-looking request
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

  test('the owner invites a family member; THEY accept, and the parent is told who joined', async () => {
    await activePlan();
    await seedSibling();
    await expect(care.requestWatcher({ userId: SIBLING, planId: PLAN, watcherId: 'someone_else' }))
      .rejects.toMatchObject({ code: 'not_owner' });

    const invited = await care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING });
    expect(invited.watchers[0]).toMatchObject({ userId: SIBLING, status: 'invited', invitedBy: CHILD });
    // The invitation goes to the person invited (as a bell row too), not to Mom.
    expect(notificationService.sendToUserWithRecord).toHaveBeenCalledWith(SIBLING, expect.objectContaining({
      type: 'care_watcher_invite', title: expect.stringContaining('Wes invited you')
    }));
    expect(notificationService.sendToUser).not.toHaveBeenCalledWith(PARENT, expect.objectContaining({ type: 'care_watcher_request' }));
    // Until they answer, their own widget shows the arrangement without answers.
    const theirs = await care.listPlans(SIBLING);
    expect(theirs.asPending.map((p) => p.planId)).toEqual([PLAN]);
    expect(theirs.asPending[0].openAsk).toBeNull();
    expect(theirs.asWatcher).toEqual([]);

    // Neither Mom nor the owner can answer an invitation for them.
    await expect(care.respondToWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING, accept: true }))
      .rejects.toMatchObject({ code: 'not_invited' });
    await expect(care.respondToWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING, accept: true }))
      .rejects.toMatchObject({ code: 'not_invited' });

    notificationService.sendToUser.mockClear();
    const joined = await care.respondToWatcher({ userId: SIBLING, planId: PLAN, watcherId: SIBLING, accept: true });
    expect(joined.role).toBe('watcher');
    expect(plans().get(PLAN).watcherIds).toEqual([SIBLING]);
    expect(plans().get(PLAN).pendingWatcherIds).toEqual([]);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({ type: 'care_watcher_accepted' }));
    expect(notificationService.sendToUser).toHaveBeenCalledWith(PARENT, expect.objectContaining({
      type: 'care_watcher_joined', title: 'Kate is now on your check-ins'
    }));
    expect((await care.listPlans(SIBLING)).asWatcher.map((p) => p.planId)).toEqual([PLAN]);
  });

  test('an invited family member may say no; the owner hears it and the row is gone', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING });
    notificationService.sendToUser.mockClear();
    const after = await care.respondToWatcher({ userId: SIBLING, planId: PLAN, watcherId: SIBLING, accept: false });
    expect(after.watchers).toEqual([]);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(CHILD, expect.objectContaining({ type: 'care_watcher_declined' }));
    expect((await care.listPlans(SIBLING)).asPending).toEqual([]);
  });

  test('a family member the owner invites may be connected to the owner OR the parent', async () => {
    await activePlan();
    await mockDb.collection(COLLECTIONS.USERS).doc(SIBLING).set({ displayName: 'Kate' });
    // Connected to the child only: the fake map is shared, so "connected" here
    // means the owner's lookup finds them after the parent's does not.
    mockConnections.delete(SIBLING);
    await expect(care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING }))
      .rejects.toMatchObject({ code: 'not_connected' });
    mockConnections.set(SIBLING, { status: 'accepted' });
    await expect(care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING })).resolves.toBeDefined();
  });

  test('a watcher asking for THEMSELVES must be connected to the PARENT, not just to the sibling', async () => {
    await activePlan();
    await mockDb.collection(COLLECTIONS.USERS).doc(SIBLING).set({ displayName: 'Kate' });
    mockConnections.delete(SIBLING);          // connected to the child, not to Mom
    await expect(care.requestWatcher({ userId: SIBLING, planId: PLAN }))
      .rejects.toMatchObject({ code: 'not_connected' });
  });

  test('the owner can send a family invitation again, after a cooldown', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: CHILD, planId: PLAN, watcherId: SIBLING });
    await expect(care.resendWatcherInvite({ userId: CHILD, planId: PLAN, watcherId: SIBLING }))
      .rejects.toMatchObject({ code: 'too_soon' });
    await expect(care.resendWatcherInvite({ userId: SIBLING, planId: PLAN, watcherId: SIBLING }))
      .rejects.toMatchObject({ code: 'not_owner' });
    const later = new Date(Date.now() + 11 * 60 * 1000);
    notificationService.sendToUserWithRecord.mockClear();
    const sent = await care.resendWatcherInvite({ userId: CHILD, planId: PLAN, watcherId: SIBLING, now: later });
    expect(sent.delivered).toBe(true);
    expect(notificationService.sendToUserWithRecord).toHaveBeenCalledWith(SIBLING, expect.objectContaining({ type: 'care_watcher_invite' }));
    expect(plans().get(PLAN).watchers[0].inviteCount).toBe(2);
    // A sibling's own request is the parent's to answer — there is nothing to resend.
    await care.respondToWatcher({ userId: SIBLING, planId: PLAN, watcherId: SIBLING, accept: false });
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    await expect(care.resendWatcherInvite({ userId: CHILD, planId: PLAN, watcherId: SIBLING, now: later }))
      .rejects.toMatchObject({ code: 'no_watcher' });
  });

  test('a sibling still waiting on the parent sees the wait in their own widget', async () => {
    await activePlan();
    await seedSibling();
    await care.requestWatcher({ userId: SIBLING, planId: PLAN });
    const listed = await care.listPlans(SIBLING);
    expect(listed.asPending.map((p) => p.role)).toEqual(['pending_watcher']);
    expect(listed.asPending[0].watchers[0]).toMatchObject({ userId: SIBLING, invitedBy: 'self' });
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
    notificationService.sendToUser.mockClear();
    expect((await care.removeWatcher({ userId: PARENT, planId: PLAN, watcherId: SIBLING })).watchers).toEqual([]);
    expect(plans().get(PLAN).watcherIds).toEqual([]);
    // The person removed is told; someone who leaves is not.
    expect(notificationService.sendToUser).toHaveBeenCalledWith(SIBLING, expect.objectContaining({ type: 'care_watcher_removed' }));
  });
});

describe('read bounds (B1b)', () => {
  test('recentAsks is bounded and newest-first, not a full plan history', async () => {
    await activePlan();
    for (let d = 1; d <= 40; d++) {
      const dateKey = `2026-08-${String(d).padStart(2, '0')}`;
      await asks().set(`${PLAN}_${dateKey}_0830`, {
        planId: PLAN, ownerId: CHILD, parentId: PARENT, slot: '08:30', dateKey, questionText: `Q${d}`,
        askedAt: `${dateKey}T12:30:00.000Z`, dueBy: `${dateKey}T15:30:00.000Z`, status: 'answered', answer: 'great', note: '', answeredAt: `${dateKey}T13:00:00.000Z`, alertedAt: null, pushDelivered: true
      });
    }
    const six = await care.recentAsks(PLAN, 6);
    expect(six).toHaveLength(6);
    expect(six.map((a) => a.questionText)).toEqual(['Q40', 'Q39', 'Q38', 'Q37', 'Q36', 'Q35']);
  });

  test('the silence sweep only touches asks past due and reads each plan once', async () => {
    await activePlan();
    await care.runDue({ now: T_0835_NY });
    const askId = [...asks().keys()][0];
    // A second, not-yet-due ask must stay open and untouched.
    await asks().set('other_open', { ...asks().get(askId), planId: PLAN, dueBy: new Date(T_0835_NY.getTime() + 9 * 3600 * 1000).toISOString(), alertedAt: null });
    const spy = jest.spyOn(mockDb, 'getAll');
    const result = await care.runDue({ now: new Date(T_0835_NY.getTime() + 3 * 3600 * 1000 + 60000) });
    expect(result.silence).toBe(1);
    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0]).toHaveLength(1); // one plan ref for the one due ask
    expect(asks().get('other_open').status).toBe('open');
    spy.mockRestore();
  });
});
