// backend/services/careCheckinService.js
//
// "How Are You?": an adult child sets up a few times a day when their parent
// gets a short question as a push, answered with one tap from the Lock
// Screen. The child sees every answer and, more importantly, the silence.
//
// Two collections, both keyed so a retried run can't double-ask:
//   carePlans/{ownerId_parentId}   the arrangement (status, questions, times, tz)
//                                  plus `watchers[]` — the other siblings. One
//                                  child sets it up, the rest join it, and the
//                                  parent is asked once rather than once each.
//   careAsks/{planId_YYYY-MM-DD_HHMM}  one question sent at one slot
//
// Every query is equality-only and sorted in memory: no composite indexes.
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { buildConnectionMap } = require('./connectionMap');
const { normalizeUserId } = require('./idService');
const notificationService = require('./notificationService');
const { localClock, localDateKey } = require('../utils/localClock');

class CareError extends ServiceError {}

const DEFAULT_QUESTIONS = [
  'How are you feeling today?',
  'Did you sleep well?',
  'Have you eaten something good today?',
  'Did you get outside today?',
  'How is your energy today?',
  'Anything on your mind?',
  'Did you take your medicine today?',
  'What made you smile today?'
];
const DEFAULT_TIMES = ['08:30', '13:00', '19:00'];
const ANSWERS = {
  great: 'Doing great 👍',
  okay: 'Okay',
  not_great: 'Not so good'
};
const MAX_QUESTIONS = 40;
const MAX_TIMES = 5;
const QUESTION_MAX = 120;
const NOTE_MAX = 200;
/** Unanswered this long after the push → the child hears about it. */
const DUE_AFTER_MS = 3 * 60 * 60 * 1000;
/** The scheduler runs every 15 minutes; a slot is "now" inside its window. */
const RUN_WINDOW_MINUTES = 15;
/** Read the plan's queue of questions across runs. */
const TYPES = {
  invite: 'care_invite',
  ask: 'care_ask',
  answer: 'care_answer',
  accepted: 'care_accepted',
  watcherRequest: 'care_watcher_request',
  watcherAccepted: 'care_watcher_accepted',
  watcherDeclined: 'care_watcher_declined',
  silence: 'care_silence'
};

const { newId, nowIso } = require('../utils/ids');
const { clean } = require('../utils/text');
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/** "08:30" → "8:30 AM" */
function friendlyTime(hhmm) {
  const [h, m] = String(hhmm).split(':').map((n) => parseInt(n, 10));
  if (!Number.isInteger(h) || !Number.isInteger(m)) return hhmm;
  const suffix = h >= 12 ? 'PM' : 'AM';
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}:${String(m).padStart(2, '0')} ${suffix}`;
}

function normalizeTimes(times) {
  if (!Array.isArray(times)) return null;
  const valid = [...new Set(times.map((t) => clean(t, 5)).filter((t) => TIME_RE.test(t)))].sort();
  if (valid.length === 0 || valid.length > MAX_TIMES) return null;
  return valid;
}

function normalizeQuestions(questions, existing = []) {
  if (!Array.isArray(questions)) return null;
  const out = [];
  for (const q of questions.slice(0, MAX_QUESTIONS)) {
    const text = clean(typeof q === 'string' ? q : q && q.text, QUESTION_MAX);
    if (!text) continue;
    const prior = existing.find((e) => e.text === text) || (q && q.id ? existing.find((e) => e.id === q.id) : null);
    out.push({ id: prior ? prior.id : newId(), text, createdAt: prior ? prior.createdAt : nowIso() });
  }
  return out;
}

class CareCheckinService {
  constructor() {
    this.db = getFirestore();
  }

  get plans() { return this.db.collection(COLLECTIONS.CARE_PLANS); }
  get asks() { return this.db.collection(COLLECTIONS.CARE_ASKS); }

  static planId(ownerId, parentId) { return `${ownerId}_${parentId}`; }

  // Who someone is on a plan. A watcher is a sibling the parent accepted; they
  // see the answers and the silences but never change the schedule — one person
  // owns the arrangement and the rest partake.
  static roleOf(plan, userId) {
    if (userId === plan.ownerId) return 'owner';
    if (userId === plan.parentId) return 'parent';
    const w = (plan.watchers || []).find((x) => x.userId === userId);
    if (w) return w.status === 'active' ? 'watcher' : 'pending_watcher';
    return 'none';
  }

  static activeWatcherIds(plan) {
    return (plan.watchers || []).filter((w) => w.status === 'active').map((w) => w.userId);
  }

  // Everyone who should hear about an answer or a silence: the child who set it
  // up plus every sibling the parent let in.
  static careTeam(plan) {
    return [plan.ownerId, ...CareCheckinService.activeWatcherIds(plan)];
  }

  static canRead(plan, userId) {
    return ['owner', 'parent', 'watcher'].includes(CareCheckinService.roleOf(plan, userId));
  }
  static askId(planId, dateKey, slot) { return `${planId}_${dateKey}_${slot.replace(':', '')}`; }

  // MARK: - Presentation

  presentPlan(plan, { asks = [], viewerId } = {}) {
    const open = asks.filter((a) => a.status === 'open').sort((a, b) => (a.askedAt < b.askedAt ? 1 : -1));
    const answered = asks.filter((a) => a.status === 'answered').sort((a, b) => (a.answeredAt < b.answeredAt ? 1 : -1));
    return {
      planId: plan.id,
      role: CareCheckinService.roleOf(plan, viewerId),
      ownerId: plan.ownerId,
      ownerName: plan.ownerName || '',
      parentId: plan.parentId,
      parentName: plan.parentName || '',
      status: plan.status,
      questions: (plan.questions || []).map((q) => ({ id: q.id, text: q.text })),
      usesDefaultQuestions: !(plan.questions || []).length,
      defaultQuestions: DEFAULT_QUESTIONS,
      times: plan.times || DEFAULT_TIMES,
      timezone: plan.timezone || null,
      createdAt: plan.createdAt || null,
      acceptedAt: plan.acceptedAt || null,
      lastAskedAt: plan.lastAskedAt || null,
      lastAnsweredAt: plan.lastAnsweredAt || null,
      watchers: (plan.watchers || []).map((w) => ({
        userId: w.userId, name: w.name || 'Someone', status: w.status,
        invitedBy: w.invitedBy || null, acceptedAt: w.acceptedAt || null
      })),
      openAsk: open[0] ? this.presentAsk({ id: open[0].id, ...open[0] }) : null,
      lastAnswer: answered[0] ? this.presentAsk({ id: answered[0].id, ...answered[0] }) : null,
      answers: ANSWERS
    };
  }

  presentAsk(ask) {
    return {
      askId: ask.id,
      planId: ask.planId,
      questionText: ask.questionText,
      slot: ask.slot,
      dateKey: ask.dateKey,
      askedAt: ask.askedAt,
      dueBy: ask.dueBy,
      status: ask.status,
      answer: ask.answer || null,
      answerText: ask.answer ? ANSWERS[ask.answer] || ask.answer : null,
      note: ask.note || '',
      answeredAt: ask.answeredAt || null,
      pushDelivered: ask.pushDelivered !== false
    };
  }

  // MARK: - Reads

  async listPlans(userId) {
    const [owned, parenting, watching] = await Promise.all([
      this.plans.where('ownerId', '==', userId).get(),
      this.plans.where('parentId', '==', userId).get(),
      // Equality on an array field: Firestore matches if the array contains it,
      // so no composite index and no second shape to keep in step.
      this.plans.where('watcherIds', 'array-contains', userId).get()
    ]);
    const seen = new Set();
    const rows = [...owned.docs, ...parenting.docs, ...watching.docs]
      .filter((d) => (seen.has(d.id) ? false : seen.add(d.id)))
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((p) => p.status !== 'ended');
    const withAsks = await Promise.all(rows.map(async (plan) => {
      const asks = await this.recentAsks(plan.id, 6);
      return this.presentPlan(plan, { asks, viewerId: userId });
    }));
    withAsks.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    return {
      asOwner: withAsks.filter((p) => p.role === 'owner'),
      asParent: withAsks.filter((p) => p.role === 'parent'),
      asWatcher: withAsks.filter((p) => p.role === 'watcher')
    };
  }

  /** Newest first, bounded by the index (planId, askedAt desc). */
  async recentAsks(planId, limit = 30) {
    const snap = await this.asks.where('planId', '==', planId).orderBy('askedAt', 'desc').limit(limit).get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  async listAsks({ userId, planId, limit = 60 }) {
    const plan = await this.requirePlan(planId);
    if (!CareCheckinService.canRead(plan, userId)) throw new CareError(403, 'not_yours', 'Not your check-in.');
    return (await this.recentAsks(planId, limit)).map((a) => this.presentAsk(a));
  }

  async requirePlan(planId) {
    const doc = await this.plans.doc(planId).get();
    if (!doc.exists) throw new CareError(404, 'no_plan', 'That check-in no longer exists.');
    return { id: doc.id, ...doc.data() };
  }

  // MARK: - Owner

  async createPlan({ ownerId, parentId, times, questions }) {
    const parent = normalizeUserId(parentId);
    if (!parent || parent === ownerId) throw new CareError(400, 'bad_parent', 'Pick someone from your connections.');
    const connections = await buildConnectionMap(ownerId);
    const link = connections.get(parent);
    if (!link || link.status !== 'accepted') throw new CareError(403, 'not_connected', 'You can only check in on someone you are connected with.');

    const [ownerDoc, parentDoc] = await Promise.all([
      this.db.collection(COLLECTIONS.USERS).doc(ownerId).get(),
      this.db.collection(COLLECTIONS.USERS).doc(parent).get()
    ]);
    if (!parentDoc.exists) throw new CareError(404, 'no_user', 'That person could not be found.');
    const ownerName = (ownerDoc.exists && ownerDoc.data().displayName) || 'Someone';
    const parentName = parentDoc.data().displayName || 'Them';
    const parentPrefs = parentDoc.data().notificationPreferences || {};

    // Someone else may already check in on this parent. Setting up a second
    // plan would ask them twice on two schedules, which is worse for the
    // parent than not being able to join at all — so say so, and hand back the
    // plan to join instead.
    const live = await this.livePlanForParent(parent);
    if (live && live.ownerId !== ownerId) {
      throw new CareError(409, 'plan_exists',
        `${live.ownerName || 'Someone'} already checks in on ${parentName}. Ask to join theirs so ${parentName} is only asked once.`,
        { planId: live.id, ownerName: live.ownerName || null });
    }

    const planId = CareCheckinService.planId(ownerId, parent);
    const existing = await this.plans.doc(planId).get();
    const prior = existing.exists ? existing.data() : {};
    if (existing.exists && (prior.status === 'active' || prior.status === 'invited' || prior.status === 'paused')) {
      throw new CareError(409, 'exists', `You already check in on ${parentName}.`);
    }
    const plan = {
      ownerId, parentId: parent, ownerName, parentName,
      status: 'invited',
      questions: normalizeQuestions(questions) || [],
      times: normalizeTimes(times) || DEFAULT_TIMES,
      timezone: parentPrefs.timezone || prior.timezone || null,
      nextQuestionIndex: 0,
      watchers: [],
      watcherIds: [],
      createdAt: nowIso(), updatedAt: nowIso(), acceptedAt: null, lastAskedAt: null, lastAnsweredAt: null
    };
    await this.plans.doc(planId).set(plan);
    this.notify(parent, {
      type: TYPES.invite,
      title: `${ownerName} wants to check in on you`,
      body: `They'll send a short "how are you?" a few times a day. Open Circles to say yes.`,
      data: { planId }
    });
    return this.presentPlan({ id: planId, ...plan }, { viewerId: ownerId });
  }

  // The live plan on a parent, whoever set it up. Equality-only, sorted in
  // memory, like every other read here.
  async livePlanForParent(parentId) {
    const snap = await this.plans.where('parentId', '==', parentId).get();
    return snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .find((p) => ['active', 'invited', 'paused'].includes(p.status)) || null;
  }

  // Tell the whole care team — the child who set it up and every sibling the
  // parent accepted. Silence and answers are exactly what a watcher joined for;
  // sending them only to the owner would make joining decorative.
  notifyTeam(plan, payload) {
    for (const userId of CareCheckinService.careTeam(plan)) this.notify(userId, payload);
  }

  // MARK: - Watchers (the other siblings)

  // A sibling asks to join, or the owner invites one. Either way the PARENT
  // decides: they already had to accept the first child, and agreeing to one
  // person seeing how you are is not agreeing to four.
  async requestWatcher({ userId, planId, watcherId = null }) {
    const plan = await this.requirePlan(planId);
    const role = CareCheckinService.roleOf(plan, userId);
    const candidate = normalizeUserId(watcherId || userId);

    if (watcherId && role !== 'owner') {
      throw new CareError(403, 'not_owner', 'Only the person who set this up can invite someone.');
    }
    if (!candidate || candidate === plan.parentId) {
      throw new CareError(400, 'bad_watcher', 'That person cannot join this check-in.');
    }
    if (candidate === plan.ownerId) throw new CareError(409, 'already_owner', 'They already run this check-in.');
    const already = (plan.watchers || []).find((w) => w.userId === candidate);
    if (already) {
      throw new CareError(409, 'already_watching',
        already.status === 'active' ? 'They are already on this check-in.' : `${plan.parentName} hasn't answered that request yet.`);
    }

    // A watcher must be connected to the PARENT, not merely to the sibling who
    // invited them — the parent's answers are the thing being shared.
    const connections = await buildConnectionMap(plan.parentId);
    const link = connections.get(candidate);
    if (!link || link.status !== 'accepted') {
      throw new CareError(403, 'not_connected', `They need to be connected with ${plan.parentName} first.`);
    }

    const doc = await this.db.collection(COLLECTIONS.USERS).doc(candidate).get();
    if (!doc.exists) throw new CareError(404, 'no_user', 'That person could not be found.');
    const name = doc.data().displayName || 'Someone';

    const watcher = {
      userId: candidate,
      name,
      status: 'invited',
      invitedBy: userId === candidate ? 'self' : userId,
      invitedAt: nowIso(),
      acceptedAt: null
    };
    await this.plans.doc(planId).update({
      watchers: [...(plan.watchers || []), watcher],
      updatedAt: nowIso()
    });

    this.notify(plan.parentId, {
      type: TYPES.watcherRequest,
      title: `${name} wants to check in on you too`,
      body: `They'd see the same answers as ${plan.ownerName || 'your family'}. Open Circles to say yes or no.`,
      data: { planId, watcherId: candidate }
    });
    const merged = { ...plan, watchers: [...(plan.watchers || []), watcher] };
    return this.presentPlan(merged, { viewerId: userId });
  }

  // Join by naming the PARENT rather than the plan. A sibling who tries to set
  // up their own check-in only knows who they meant to watch, not the id of the
  // arrangement someone else already made — so this resolves it for them.
  async requestWatcherForParent({ userId, parentId }) {
    const parent = normalizeUserId(parentId);
    const plan = parent ? await this.livePlanForParent(parent) : null;
    if (!plan) throw new CareError(404, 'no_plan', 'Nobody is checking in on them yet — set one up instead.');
    return this.requestWatcher({ userId, planId: plan.id });
  }

  // The parent says yes or no. Only the parent — the owner cannot wave a
  // sibling through on their behalf.
  async respondToWatcher({ userId, planId, watcherId, accept }) {
    const plan = await this.requirePlan(planId);
    if (plan.parentId !== userId) {
      throw new CareError(403, 'not_parent', 'Only the person being checked in on can answer this.');
    }
    const target = normalizeUserId(watcherId);
    const watcher = (plan.watchers || []).find((w) => w.userId === target);
    if (!watcher) throw new CareError(404, 'no_watcher', 'That request is no longer there.');

    const watchers = accept
      ? (plan.watchers || []).map((w) => (w.userId === target ? { ...w, status: 'active', acceptedAt: nowIso() } : w))
      : (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: CareCheckinService.activeWatcherIds(merged),
      updatedAt: nowIso()
    });

    this.notify(target, accept ? {
      type: TYPES.watcherAccepted,
      title: `You're on ${plan.parentName}'s check-ins`,
      body: `You'll see their answers, and hear about it when a question goes unanswered.`,
      data: { planId }
    } : {
      type: TYPES.watcherDeclined,
      title: `${plan.parentName} said no for now`,
      body: 'They chose not to add you to their check-ins.',
      data: { planId }
    });
    return this.presentPlan(merged, { viewerId: userId });
  }

  // Leaving, or being removed. A watcher can always take themselves off; the
  // parent and the owner can remove anyone.
  async removeWatcher({ userId, planId, watcherId }) {
    const plan = await this.requirePlan(planId);
    const target = normalizeUserId(watcherId);
    const isSelf = target === userId;
    if (!isSelf && plan.parentId !== userId && plan.ownerId !== userId) {
      throw new CareError(403, 'not_allowed', 'Only they, the owner, or the person being checked in on can do that.');
    }
    const watchers = (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: CareCheckinService.activeWatcherIds(merged),
      updatedAt: nowIso()
    });
    return this.presentPlan(merged, { viewerId: userId });
  }

  async updatePlan({ userId, planId, times, questions, status }) {
    const plan = await this.requirePlan(planId);
    if (plan.ownerId !== userId) throw new CareError(403, 'not_owner', 'Only the person who set this up can change it.');
    const patch = { updatedAt: nowIso() };
    if (times !== undefined) {
      const t = normalizeTimes(times);
      if (!t) throw new CareError(400, 'bad_times', 'Pick between one and five times, like 08:30.');
      patch.times = t;
    }
    if (questions !== undefined) {
      const q = normalizeQuestions(questions, plan.questions || []);
      if (!q) throw new CareError(400, 'bad_questions', 'Questions must be a list.');
      patch.questions = q;
      patch.nextQuestionIndex = 0;
    }
    if (status !== undefined) {
      if (!['active', 'paused'].includes(status)) throw new CareError(400, 'bad_status', 'Status must be active or paused.');
      if (!plan.acceptedAt) throw new CareError(409, 'not_accepted', `${plan.parentName} hasn't accepted yet.`);
      patch.status = status;
    }
    await this.plans.doc(planId).update(patch);
    const merged = { ...plan, ...patch };
    return this.presentPlan(merged, { asks: await this.recentAsks(planId, 6), viewerId: userId });
  }

  async endPlan({ userId, planId }) {
    const plan = await this.requirePlan(planId);
    if (plan.ownerId !== userId && plan.parentId !== userId) throw new CareError(403, 'not_yours', 'Not your check-in.');
    await this.plans.doc(planId).update({ status: 'ended', endedBy: userId, updatedAt: nowIso() });
    return { planId, status: 'ended' };
  }

  // MARK: - Parent

  async respondToInvite({ userId, planId, accept, timezone }) {
    const plan = await this.requirePlan(planId);
    if (plan.parentId !== userId) throw new CareError(403, 'not_parent', 'This invitation is for someone else.');
    if (plan.status === 'ended') throw new CareError(409, 'ended', 'This check-in was ended.');
    const patch = { updatedAt: nowIso() };
    if (accept) {
      patch.status = 'active';
      patch.acceptedAt = plan.acceptedAt || nowIso();
      const tz = clean(timezone, 64);
      if (tz) {
        try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); patch.timezone = tz; } catch (error) { /* keep prior */ }
      }
    } else {
      patch.status = 'declined';
    }
    await this.plans.doc(planId).update(patch);
    const merged = { ...plan, ...patch };
    if (accept) {
      const next = this.nextSlot(merged);
      // Deliberately the owner only: this answers the invitation they sent.
      this.notify(plan.ownerId, {
        type: TYPES.accepted,
        title: `${plan.parentName} said yes to check-ins`,
        body: next ? `The first question goes out at ${friendlyTime(next)} their time.` : 'Questions start at the times you chose.',
        data: { planId }
      });
    }
    return this.presentPlan(merged, { viewerId: userId });
  }

  async answerAsk({ userId, askId, answer, note }) {
    const doc = await this.asks.doc(askId).get();
    if (!doc.exists) throw new CareError(404, 'no_ask', 'That question has expired.');
    const ask = { id: doc.id, ...doc.data() };
    if (ask.parentId !== userId) throw new CareError(403, 'not_parent', 'This question is for someone else.');
    if (!ANSWERS[answer]) throw new CareError(400, 'bad_answer', 'Answer must be great, okay or not_great.');
    if (ask.status === 'answered') {
      return this.presentAsk(ask);
    }
    const patch = { status: 'answered', answer, note: clean(note, NOTE_MAX), answeredAt: nowIso() };
    await this.asks.doc(askId).update(patch);
    await this.plans.doc(ask.planId).update({ lastAnsweredAt: patch.answeredAt, updatedAt: nowIso() });
    const plan = await this.plans.doc(ask.planId).get();
    const parentName = (plan.exists && plan.data().parentName) || 'They';
    const noteLine = patch.note ? ` — "${patch.note}"` : '';
    this.notifyTeam(plan.exists ? { id: plan.id, ...plan.data() } : { ownerId: ask.ownerId }, {
      type: TYPES.answer,
      title: `${parentName}: ${ANSWERS[answer]}`,
      body: `“${ask.questionText}”${noteLine}`,
      data: { planId: ask.planId, askId, answer }
    });
    return this.presentAsk({ ...ask, ...patch });
  }

  // MARK: - The scheduler

  /** The next configured slot after the parent's current local time, if any today. */
  nextSlot(plan, now = new Date()) {
    const clock = localClock(plan.timezone, now);
    const times = plan.times || DEFAULT_TIMES;
    return times.find((t) => {
      const [h, m] = t.split(':').map((n) => parseInt(n, 10));
      return h * 60 + m > clock.minutes;
    }) || times[0];
  }

  /** Questions in rotation: the owner's own, or the defaults. */
  pickQuestion(plan) {
    const pool = (plan.questions || []).length ? plan.questions : DEFAULT_QUESTIONS.map((text, i) => ({ id: `default_${i}`, text }));
    const index = Number.isInteger(plan.nextQuestionIndex) ? plan.nextQuestionIndex % pool.length : 0;
    return { question: pool[index], nextIndex: (index + 1) % pool.length };
  }

  /**
   * Runs every 15 minutes. Sends each active plan's questions whose slot fell
   * inside the window that just closed (parent-local), then raises the
   * silence alerts for questions unanswered past their due time.
   */
  async runDue({ now = new Date() } = {}) {
    const summary = { plans: 0, asked: 0, silence: 0, undelivered: 0, errors: 0 };
    const snap = await this.plans.where('status', '==', 'active').get();
    for (const doc of snap.docs) {
      const plan = { id: doc.id, ...doc.data() };
      summary.plans += 1;
      try {
        summary.asked += await this.askDueSlots(plan, now);
      } catch (error) {
        summary.errors += 1;
        console.error(`[care] ask failed for ${plan.id}: ${error.message}`);
      }
    }
    try {
      const alerts = await this.raiseSilenceAlerts(now);
      summary.silence += alerts.silence;
      summary.undelivered += alerts.undelivered;
    } catch (error) {
      summary.errors += 1;
      console.error(`[care] silence sweep failed: ${error.message}`);
    }
    return summary;
  }

  async askDueSlots(plan, now) {
    const clock = localClock(plan.timezone, now);
    const dateKey = localDateKey(plan.timezone, now);
    let sent = 0;
    let nextIndex = plan.nextQuestionIndex;
    for (const slot of plan.times || DEFAULT_TIMES) {
      const [h, m] = slot.split(':').map((n) => parseInt(n, 10));
      const slotMinutes = h * 60 + m;
      const delta = clock.minutes - slotMinutes;
      if (delta < 0 || delta >= RUN_WINDOW_MINUTES) continue;
      const askId = CareCheckinService.askId(plan.id, dateKey, slot);
      const { question, nextIndex: after } = this.pickQuestion({ ...plan, nextQuestionIndex: nextIndex });
      const ask = {
        planId: plan.id, ownerId: plan.ownerId, parentId: plan.parentId,
        slot, dateKey, questionId: question.id, questionText: question.text,
        askedAt: now.toISOString(), dueBy: new Date(now.getTime() + DUE_AFTER_MS).toISOString(),
        status: 'open', answer: null, note: '', answeredAt: null, alertedAt: null, pushDelivered: null, pushError: null
      };
      try {
        await this.asks.doc(askId).create(ask);
      } catch (error) {
        continue; // already asked this slot today (a retried run)
      }
      nextIndex = after;
      const result = await this.push(plan.parentId, {
        type: TYPES.ask,
        title: `${plan.ownerName || 'Your family'} asks`,
        body: question.text,
        data: { planId: plan.id, askId, questionText: question.text }
      });
      await this.asks.doc(askId).update({ pushDelivered: !!(result && result.success), pushError: result && result.error ? String(result.error) : null });
      sent += 1;
    }
    if (sent > 0) {
      await this.plans.doc(plan.id).update({ nextQuestionIndex: nextIndex, lastAskedAt: now.toISOString(), updatedAt: nowIso() });
    }
    return sent;
  }

  /**
   * "Didn't answer" and "never got it" are different alarms. A push the
   * phone never received (no tokens, quiet hours, signed out) must not be
   * reported as the parent going quiet.
   */
  async raiseSilenceAlerts(now) {
    const counts = { silence: 0, undelivered: 0 };
    // Only asks past their due time (index: status, dueBy) — never the whole
    // open set — and each plan read once for the run.
    const snap = await this.asks.where('status', '==', 'open').where('dueBy', '<=', now.toISOString()).limit(500).get();
    const due = snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter((a) => !a.alertedAt);
    const planIds = [...new Set(due.map((a) => a.planId))];
    const planDocs = planIds.length ? await this.db.getAll(...planIds.map((id) => this.plans.doc(id))) : [];
    const plansById = new Map(planDocs.map((d) => [d.id, d]));
    const undeliveredNoticed = new Set();
    for (const ask of due) {
      const planDoc = plansById.get(ask.planId);
      if (!planDoc || !planDoc.exists || planDoc.data().status !== 'active') {
        await this.asks.doc(ask.id).update({ status: 'missed', alertedAt: now.toISOString(), alertKind: 'none' });
        continue;
      }
      const plan = { id: planDoc.id, ...planDoc.data() };
      if (ask.pushDelivered === false) {
        const key = `${plan.id}_${ask.dateKey}`;
        if (!undeliveredNoticed.has(key) && !(plan.undeliveredNoticedOn === ask.dateKey)) {
          undeliveredNoticed.add(key);
          await this.plans.doc(plan.id).update({ undeliveredNoticedOn: ask.dateKey });
          this.notifyTeam(plan, {
            type: TYPES.silence,
            title: `${plan.parentName}'s phone isn't getting check-ins`,
            body: `Today's question couldn't be delivered. Notifications may be off, or Circles is signed out on their phone.`,
            data: { planId: plan.id, askId: ask.id, kind: 'undelivered' }
          });
          counts.undelivered += 1;
        }
        await this.asks.doc(ask.id).update({ status: 'missed', alertedAt: now.toISOString(), alertKind: 'undelivered' });
        continue;
      }
      this.notifyTeam(plan, {
        type: TYPES.silence,
        title: `${plan.parentName} hasn't answered`,
        body: `“${ask.questionText}” went out at ${friendlyTime(ask.slot)} their time and hasn't been answered.`,
        data: { planId: plan.id, askId: ask.id, kind: 'silence' }
      });
      await this.asks.doc(ask.id).update({ status: 'missed', alertedAt: now.toISOString(), alertKind: 'silence' });
      counts.silence += 1;
    }
    return counts;
  }

  // MARK: - Push

  /** Awaited: the delivery result decides which alarm the child gets later. */
  async push(userId, { type, title, body, data }) {
    try {
      return await notificationService.sendToUser(userId, { type, title, body, data: { type, ...(data || {}) } });
    } catch (error) {
      console.error(`[care] push failed for ${userId}: ${error.message}`);
      return { success: false, error: error.message };
    }
  }

  /** Fire-and-forget, for notices whose delivery nothing depends on. */
  notify(userId, payload) {
    this.push(userId, payload).catch(() => {});
  }
}

module.exports = Object.assign(new CareCheckinService(), {
  CareError, DEFAULT_QUESTIONS, DEFAULT_TIMES, ANSWERS, TYPES, DUE_AFTER_MS, localDateKey, friendlyTime
});
