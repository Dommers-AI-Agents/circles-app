// services/careCheckin/scheduler.js — methods of CareCheckinService (mixed into its prototype by the facade).
const { COLLECTIONS, DEFAULT_TIMES, DUE_AFTER_MS, RICH_ASKS_MIN_CLIENT, RUN_WINDOW_MINUTES, TYPES, bank, friendlyTime, localClock, localDateKey, nowIso } = require('./shared');
const planner = require('./questionPlanner');
const { anyDeviceAtLeast } = require('../../utils/appVersion');

/** How much history the planner sees: ~a month at three questions a day. */
const RECENT_FOR_PLANNING = 90;

module.exports = {
  nextSlot(plan, now = new Date()) {
    const clock = localClock(plan.timezone, now);
    const times = plan.times || DEFAULT_TIMES;
    return times.find((t) => {
      const [h, m] = t.split(':').map((n) => parseInt(n, 10));
      return h * 60 + m > clock.minutes;
    }) || times[0];
  },

  /**
   * The question for one slot: the bank filtered by the care profile, the
   * owner's own questions, what was asked lately, and whether the parent's
   * app can answer anything beyond the three mood buttons. Pure inside
   * (questionPlanner.js); this only gathers the inputs.
   */
  pickQuestion(plan, { slot, dateKey, weekday, recent = [], capable = false }) {
    return planner.pick({
      profile: plan.profile || {}, custom: plan.questions || [], muted: plan.mutedQuestionIds || [],
      capable, slot, slots: plan.times || DEFAULT_TIMES, dateKey, weekday, recent
    });
  },

  /** Whether the parent's app has the Lock Screen buttons for non-mood questions. */
  async parentCanAnswerRich(plan) {
    const doc = await this.db.collection(COLLECTIONS.USERS).doc(plan.parentId).get();
    return doc.exists && anyDeviceAtLeast(doc.data().deviceTokens, RICH_ASKS_MIN_CLIENT);
  },

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
  },

  async askDueSlots(plan, now) {
    const clock = localClock(plan.timezone, now);
    const dateKey = localDateKey(plan.timezone, now);
    let sent = 0;
    let context = null; // gathered once, only when a slot is actually due
    for (const slot of plan.times || DEFAULT_TIMES) {
      const [h, m] = slot.split(':').map((n) => parseInt(n, 10));
      const slotMinutes = h * 60 + m;
      const delta = clock.minutes - slotMinutes;
      if (delta < 0 || delta >= RUN_WINDOW_MINUTES) continue;
      const askId = this.constructor.askId(plan.id, dateKey, slot);
      if (!context) {
        const [recent, capable] = await Promise.all([this.recentAsks(plan.id, RECENT_FOR_PLANNING), this.parentCanAnswerRich(plan)]);
        context = { recent: recent.map((a) => ({ questionId: a.questionId, dateKey: a.dateKey })), capable, weekday: clock.weekday };
      }
      const question = this.pickQuestion(plan, { slot, dateKey, ...context });
      if (!question) continue; // everything in rotation was already asked today
      const meta = bank.kindMeta(question);
      const ask = {
        planId: plan.id, ownerId: plan.ownerId, parentId: plan.parentId,
        slot, dateKey, questionId: question.id, questionText: question.text,
        kind: meta.kind, short: meta.short || null, low: meta.low || null, high: meta.high || null,
        alertRule: question.alert || null,
        askedAt: now.toISOString(), dueBy: new Date(now.getTime() + DUE_AFTER_MS).toISOString(),
        status: 'open', answer: null, answerValue: null, answerScore: null, answerText: null, alert: false,
        note: '', answeredAt: null, alertedAt: null, pushDelivered: null, pushError: null
      };
      try {
        await this.asks.doc(askId).create(ask);
      } catch (error) {
        continue; // already asked this slot today (a retried run)
      }
      // The same question again in this run's planning window
      context.recent.unshift({ questionId: question.id, dateKey });
      const result = await this.push(plan.parentId, {
        type: TYPES.askByKind[meta.kind] || TYPES.ask,
        title: `${plan.ownerName || 'Your family'} asks`,
        body: question.text,
        data: { planId: plan.id, askId, questionText: question.text, kind: meta.kind }
      });
      await this.asks.doc(askId).update({ pushDelivered: !!(result && result.success), pushError: result && result.error ? String(result.error) : null });
      sent += 1;
    }
    if (sent > 0) {
      await this.plans.doc(plan.id).update({ lastAskedAt: now.toISOString(), parentCanAnswerRich: context.capable, updatedAt: nowIso() });
    }
    return sent;
  },

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
  },
};
