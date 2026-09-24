// backend/services/careCheckinService.js
// "How Are You?" check-ins between a parent and their children.
// Plans, asks and answers here; membership (watchers) and scheduler (ask creation, silence alerts) are mixed in from ./careCheckin.
// Constants and pure helpers live in ./careCheckin/shared.js.
// A resent invitation is a nudge to a real phone; ten minutes between them.
const RESEND_INVITE_COOLDOWN_MS = 10 * 60 * 1000;
const { ANSWERS, COLLECTIONS, CareError, DEFAULT_QUESTIONS, DEFAULT_TIMES, DUE_AFTER_MS, NOTE_MAX, RICH_ASKS_MIN_CLIENT, TYPES, bank, buildConnectionMap, clean, friendlyTime, getFirestore, localDateKey, normalizeMuted, normalizeProfile, normalizeQuestions, normalizeTimes, normalizeUserId, notificationService, nowIso } = require('./careCheckin/shared');
const planner = require('./careCheckin/questionPlanner');
const { atLeast } = require('../utils/appVersion');

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
      questions: (plan.questions || []).map((q) => CareCheckinService.presentQuestion(q)),
      usesDefaultQuestions: !(plan.questions || []).length,
      defaultQuestions: DEFAULT_QUESTIONS,
      // The care profile (owner's answers about the parent) and what it
      // puts in rotation. `profile` null = the questionnaire hasn't been done.
      profile: plan.profile || null,
      profileFields: bank.PROFILE_FIELDS,
      mutedQuestionIds: plan.mutedQuestionIds || [],
      rotation: planner.rotation({ profile: plan.profile || {}, custom: plan.questions || [], muted: plan.mutedQuestionIds || [] })
        .map((q) => CareCheckinService.presentQuestion(q)),
      // Whether the parent's app can answer more than the three mood buttons.
      // Until it can, only mood questions go out (see the scheduler).
      parentCanAnswerRich: plan.parentCanAnswerRich === true,
      times: plan.times || DEFAULT_TIMES,
      timezone: plan.timezone || null,
      createdAt: plan.createdAt || null,
      lastInvitedAt: plan.lastInvitedAt || plan.createdAt || null,
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

  static presentQuestion(q) {
    // An own question from before kinds has none stored: it is a plain yes/no.
    const out = { id: q.id, text: q.text, ...bank.kindMeta({ ...q, kind: bank.KINDS.includes(q.kind) ? q.kind : planner.LEGACY_OWN_KIND }) };
    out.source = q.source || 'custom';
    out.muted = q.muted === true;
    out.cadence = bank.cadenceLabel(q);
    out.requires = q.requires || null;
    return out;
  }

  presentAsk(ask) {
    const kind = bank.KINDS.includes(ask.kind) ? ask.kind : 'mood';
    return {
      askId: ask.id,
      planId: ask.planId,
      questionText: ask.questionText,
      kind,
      short: ask.short || null,
      low: ask.low || null,
      high: ask.high || null,
      slot: ask.slot,
      dateKey: ask.dateKey,
      askedAt: ask.askedAt,
      dueBy: ask.dueBy,
      status: ask.status,
      // `answer` is the choice key (older clients render the mood ones);
      // `answerValue`/`answerScore` carry scales and typed answers;
      // `answerText` is always the words to show.
      answer: ask.answer || null,
      answerValue: ask.answerValue !== undefined && ask.answerValue !== null ? String(ask.answerValue) : (ask.answer || null),
      answerScore: Number.isInteger(ask.answerScore) ? ask.answerScore : null,
      answerText: ask.answerText || (ask.answer ? ANSWERS[ask.answer] || ask.answer : null),
      alert: ask.alert === true,
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

  async createPlan({ ownerId, parentId, times, questions, profile }) {
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
      profile: normalizeProfile(profile),
      mutedQuestionIds: [],
      times: normalizeTimes(times) || DEFAULT_TIMES,
      timezone: parentPrefs.timezone || prior.timezone || null,
      nextQuestionIndex: 0,
      watchers: [],
      watcherIds: [],
      createdAt: nowIso(), updatedAt: nowIso(), lastInvitedAt: nowIso(), inviteCount: 1,
      acceptedAt: null, lastAskedAt: null, lastAnsweredAt: null
    };
    await this.plans.doc(planId).set(plan);
    this.notify(parent, CareCheckinService.inviteMessage(ownerName, planId));
    return this.presentPlan({ id: planId, ...plan }, { viewerId: ownerId });
  }

  static inviteMessage(ownerName, planId) {
    return {
      type: TYPES.invite,
      title: `${ownerName} wants to check in on you`,
      body: `They'll send a short "how are you?" a few times a day. Open Circles to say yes.`,
      data: { planId }
    };
  }

  // The invitation push again, for a parent who missed it (an old app, a
  // phone that was off). The plan itself is unchanged: it was already waiting
  // in their widget. Awaited so the child hears whether the phone got it.
  async resendInvite({ userId, planId, now = new Date() }) {
    const plan = await this.requirePlan(planId);
    if (plan.ownerId !== userId) throw new CareError(403, 'not_owner', 'Only the person who set this up can send the invitation again.');
    if (plan.status !== 'invited') {
      const why = plan.status === 'declined' ? `${plan.parentName} said no to this one.` : `${plan.parentName} already answered the invitation.`;
      throw new CareError(409, 'not_invited', why);
    }
    const last = Date.parse(plan.lastInvitedAt || plan.createdAt || 0) || 0;
    const waitMs = RESEND_INVITE_COOLDOWN_MS - (now.getTime() - last);
    if (waitMs > 0) {
      const minutes = Math.max(1, Math.ceil(waitMs / 60000));
      throw new CareError(429, 'too_soon', `The invitation just went out. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`);
    }
    const result = await this.push(plan.parentId, CareCheckinService.inviteMessage(plan.ownerName || 'Someone', planId));
    const patch = { lastInvitedAt: now.toISOString(), inviteCount: (plan.inviteCount || 1) + 1, updatedAt: nowIso() };
    await this.plans.doc(planId).update(patch);
    return {
      plan: this.presentPlan({ ...plan, ...patch }, { viewerId: userId }),
      delivered: !!(result && result.success)
    };
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

  async updatePlan({ userId, planId, times, questions, status, profile, mutedQuestionIds }) {
    const plan = await this.requirePlan(planId);
    if (plan.ownerId !== userId) throw new CareError(403, 'not_owner', 'Only the person who set this up can change it.');
    const patch = { updatedAt: nowIso() };
    if (profile !== undefined) {
      const p = normalizeProfile(profile);
      if (!p) throw new CareError(400, 'bad_profile', 'The care profile must be a set of yes/no answers.');
      patch.profile = p;
    }
    if (mutedQuestionIds !== undefined) {
      const m = normalizeMuted(mutedQuestionIds);
      if (!m) throw new CareError(400, 'bad_muted', 'Muted questions must be a list.');
      patch.mutedQuestionIds = m;
    }
    if (times !== undefined) {
      const t = normalizeTimes(times);
      if (!t) throw new CareError(400, 'bad_times', 'Pick between one and five times, like 08:30.');
      patch.times = t;
    }
    if (questions !== undefined) {
      const q = normalizeQuestions(questions, plan.questions || []);
      if (!q) throw new CareError(400, 'bad_questions', 'Questions must be a list.');
      patch.questions = q;
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

  async respondToInvite({ userId, planId, accept, timezone, client }) {
    const plan = await this.requirePlan(planId);
    if (plan.parentId !== userId) throw new CareError(403, 'not_parent', 'This invitation is for someone else.');
    if (plan.status === 'ended') throw new CareError(409, 'ended', 'This check-in was ended.');
    const patch = { updatedAt: nowIso() };
    // The parent's own app just spoke to us: the surest word on what it can render.
    if (client && atLeast(client, RICH_ASKS_MIN_CLIENT)) patch.parentCanAnswerRich = true;
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

  /**
   * The parent answers. `answer` is a choice key (mood / done / yesno);
   * `value` is the number for a 0–10 question or the words for a typed one.
   * Either field is accepted for any kind so an older client's `answer`
   * keeps working. An answer the question names as worrying (pain 7+,
   * "no" to medicine, "yes" to a fall) reaches the family as a heads-up.
   */
  async answerAsk({ userId, askId, answer, value, note, client }) {
    const doc = await this.asks.doc(askId).get();
    if (!doc.exists) throw new CareError(404, 'no_ask', 'That question has expired.');
    const ask = { id: doc.id, ...doc.data() };
    if (ask.parentId !== userId) throw new CareError(403, 'not_parent', 'This question is for someone else.');
    const question = { kind: ask.kind || 'mood', short: ask.short, alert: ask.alertRule || null };
    const resolved = bank.resolveAnswer(question, { answer, value });
    if (!resolved) throw new CareError(400, 'bad_answer', CareCheckinService.badAnswerMessage(question.kind));
    if (ask.status === 'answered') {
      return this.presentAsk(ask);
    }
    const alert = bank.isAlertAnswer(question, resolved);
    const patch = {
      status: 'answered', answer: resolved.answer, answerValue: resolved.answerValue, answerScore: resolved.answerScore,
      answerText: resolved.answerText, alert, note: clean(note, NOTE_MAX), answeredAt: nowIso()
    };
    await this.asks.doc(askId).update(patch);
    const planPatch = { lastAnsweredAt: patch.answeredAt, updatedAt: nowIso() };
    if (client && atLeast(client, RICH_ASKS_MIN_CLIENT)) planPatch.parentCanAnswerRich = true;
    await this.plans.doc(ask.planId).update(planPatch);
    const plan = await this.plans.doc(ask.planId).get();
    const parentName = (plan.exists && plan.data().parentName) || 'They';
    const noteLine = patch.note ? ` — "${patch.note}"` : '';
    this.notifyTeam(plan.exists ? { id: plan.id, ...plan.data() } : { ownerId: ask.ownerId }, {
      type: TYPES.answer,
      title: `${alert ? 'Heads up · ' : ''}${parentName}: ${resolved.answerText}`,
      body: `“${ask.questionText}”${noteLine}`,
      data: { planId: ask.planId, askId, answer: resolved.answerValue, kind: resolved.kind, alert: alert ? '1' : '0' }
    });
    return this.presentAsk({ ...ask, ...patch });
  }

  static badAnswerMessage(kind) {
    switch (kind) {
      case 'scale': return 'Answer with a number from 0 to 10.';
      case 'text': return 'Type a few words.';
      case 'done': return 'Answer must be yes, not_yet or no.';
      case 'yesno': return 'Answer must be yes or no.';
      default: return 'Answer must be great, okay or not_great.';
    }
  }

  // MARK: - The scheduler

  /** The next configured slot after the parent's current local time, if any today. */

  // MARK: - Push

  /** Awaited: the delivery result decides which alarm the child gets later. */
  async push(userId, { type, title, body, data }) {
    try {
      const payload = { type, title, body, data: { type, ...(data || {}) } };
      // An invitation and its answer are things people go back to look for;
      // they get a bell row as well as the push. The rest are moment-to-moment.
      const keep = type === TYPES.invite || type === TYPES.accepted;
      return keep
        ? await notificationService.sendToUserWithRecord(userId, payload)
        : await notificationService.sendToUser(userId, payload);
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

Object.assign(CareCheckinService.prototype, require('./careCheckin/membership'), require('./careCheckin/scheduler'));
module.exports = Object.assign(new CareCheckinService(), {
  CareError, DEFAULT_QUESTIONS, DEFAULT_TIMES, ANSWERS, TYPES, DUE_AFTER_MS, RICH_ASKS_MIN_CLIENT, localDateKey, friendlyTime
});
