// services/careCheckin/scheduler.js — methods of CareCheckinService (mixed into its prototype by the facade).
const { DEFAULT_QUESTIONS, DEFAULT_TIMES, DUE_AFTER_MS, RUN_WINDOW_MINUTES, TYPES, friendlyTime, localClock, localDateKey, nowIso } = require('./shared');

module.exports = {
  nextSlot(plan, now = new Date()) {
    const clock = localClock(plan.timezone, now);
    const times = plan.times || DEFAULT_TIMES;
    return times.find((t) => {
      const [h, m] = t.split(':').map((n) => parseInt(n, 10));
      return h * 60 + m > clock.minutes;
    }) || times[0];
  },

  /** Questions in rotation: the owner's own, or the defaults. */
  pickQuestion(plan) {
    const pool = (plan.questions || []).length ? plan.questions : DEFAULT_QUESTIONS.map((text, i) => ({ id: `default_${i}`, text }));
    const index = Number.isInteger(plan.nextQuestionIndex) ? plan.nextQuestionIndex % pool.length : 0;
    return { question: pool[index], nextIndex: (index + 1) % pool.length };
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
    let nextIndex = plan.nextQuestionIndex;
    for (const slot of plan.times || DEFAULT_TIMES) {
      const [h, m] = slot.split(':').map((n) => parseInt(n, 10));
      const slotMinutes = h * 60 + m;
      const delta = clock.minutes - slotMinutes;
      if (delta < 0 || delta >= RUN_WINDOW_MINUTES) continue;
      const askId = this.constructor.askId(plan.id, dateKey, slot);
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
