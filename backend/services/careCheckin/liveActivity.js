// services/careCheckin/liveActivity.js — methods of CareCheckinService (mixed
// into its prototype by the facade), plus the pure content builder.
//
// A How Are You? question stays on the parent's Lock Screen until they answer
// it (Wes, 2026-10-30: "persistent notification so a user doesn't miss the
// question"). iOS can't pin a notification, so the question is ALSO started
// as a Live Activity by push (push-to-start, iOS 17.2+), with the answer
// buttons on it. Answering anywhere ends it; the next question replaces it.
// A phone that can't show one (older iOS, Live Activities off) gets the
// question pushed once more an hour later instead.
const { COLLECTIONS, DUE_AFTER_MS, TYPES, bank, nowIso } = require('./shared');
const liveActivityPush = require('../liveActivityPush');

/** Swift struct name the app registers (CareQuestionAttributes). Must match exactly. */
const ATTRIBUTES_TYPE = 'CareQuestionAttributes';
/** Unanswered this long with no Lock Screen display on the phone: ask once more. */
const REMIND_AFTER_MS = 60 * 60 * 1000;
/** iOS keeps a Live Activity active at most 8 hours; ask it to show as stale at the due time. */
const START_TOKENS = 'careLiveStartTokens';

/**
 * What the Lock Screen shows (pure, tested). Keys and shapes match the app's
 * CareQuestionAttributes.ContentState exactly: no Dates, nulls for absent.
 */
function contentState(ask, { answered = false, answerText = null } = {}) {
  const kind = ask.kind || 'mood';
  const choices = Object.entries(bank.CHOICES[kind] || {}).map(([key, label]) => ({ key, label }));
  return {
    question: ask.questionText,
    kind,
    choices,
    low: kind === 'scale' ? (ask.low || '0') : null,
    high: kind === 'scale' ? (ask.high || '10') : null,
    answered: !!answered,
    answerText: answered ? (answerText || null) : null
  };
}

function attributesFor(ask, plan) {
  return { askId: ask.id, planId: ask.planId, fromName: (plan && plan.ownerName) || 'Your family' };
}

const seconds = (iso) => Math.floor(new Date(iso).getTime() / 1000);

const methods = {
  get liveStartTokens() { return this.db.collection(START_TOKENS); },

  /** The parent's phone can be sent a question to show (push-to-start). */
  async registerLiveStartToken(userId, { token, fcmToken }) {
    if (!token || !fcmToken) return { registered: false };
    await this.liveStartTokens.doc(userId).set({ token: String(token), fcmToken: String(fcmToken), updatedAt: nowIso() });
    return { registered: true };
  },

  /** A question is on the parent's Lock Screen: keep its own push token so answering can end it. */
  async registerAskLiveToken(userId, askId, { token, fcmToken }) {
    if (!token || !fcmToken) return { registered: false };
    const doc = await this.asks.doc(askId).get();
    if (!doc.exists || doc.data().parentId !== userId) return { registered: false };
    await this.asks.doc(askId).update({ liveToken: String(token), liveFcmToken: String(fcmToken), liveShownAt: nowIso() });
    // Answered between the start and this upload: take it down now
    if (doc.data().status === 'answered') await this.endAskLiveActivity({ id: askId, ...doc.data(), liveToken: token, liveFcmToken: fcmToken });
    return { registered: true };
  },

  /**
   * Put a just-sent question on the parent's Lock Screen. Any older question
   * from the same plan still showing comes down first: one question at a time.
   */
  async startAskLiveActivity(plan, ask) {
    try {
      await this.endOtherOpenAskActivities(plan.id, ask.id);
      const doc = await this.liveStartTokens.doc(plan.parentId).get();
      if (!doc.exists) return false;
      const { token, fcmToken } = doc.data();
      const ok = await liveActivityPush.sendLiveActivity({
        fcmToken, token, event: 'start',
        state: contentState(ask),
        attributesType: ATTRIBUTES_TYPE,
        attributes: attributesFor(ask, plan),
        // The start push is what shows when it arrives; the normal question
        // push already rang, so this one is silent
        alert: { title: `${plan.ownerName || 'Your family'} asks`, body: ask.questionText },
        staleDate: seconds(ask.dueBy)
      });
      if (ok === 'gone') await doc.ref.delete().catch(() => {});
      return ok === true;
    } catch (error) {
      console.error(`[care] live activity start failed for ${ask.id}: ${error.message}`);
      return false;
    }
  },

  /** Take a question off the Lock Screen, showing the answer for a moment when there is one. */
  async endAskLiveActivity(ask, { answerText = null } = {}) {
    if (!ask || !ask.liveToken || !ask.liveFcmToken) return false;
    try {
      const now = Math.floor(Date.now() / 1000);
      const answered = !!answerText;
      const ok = await liveActivityPush.sendLiveActivity({
        fcmToken: ask.liveFcmToken, token: ask.liveToken, event: 'end',
        state: contentState(ask, { answered, answerText }),
        // Answered: "Sent: Doing great" for a minute. Replaced: gone at once.
        dismissalDate: answered ? now + 60 : now
      });
      await this.asks.doc(ask.id).update({ liveToken: null, liveFcmToken: null, liveEndedAt: nowIso() }).catch(() => {});
      return ok === true;
    } catch (error) {
      console.error(`[care] live activity end failed for ${ask.id}: ${error.message}`);
      return false;
    }
  },

  async endOtherOpenAskActivities(planId, keepAskId) {
    const snap = await this.asks.where('planId', '==', planId).where('status', '==', 'open').get();
    const showing = snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter((a) => a.id !== keepAskId && a.liveToken);
    await Promise.all(showing.map((a) => this.endAskLiveActivity(a)));
  },

  /**
   * Questions still open an hour on, on a phone that shows no Lock Screen
   * display for them (no activity token came back): push the question once
   * more, buttons and all. Uses the silence sweep's (status, dueBy) index.
   */
  async remindUnanswered(now = new Date()) {
    const horizon = new Date(now.getTime() + DUE_AFTER_MS - REMIND_AFTER_MS).toISOString();
    const snap = await this.asks.where('status', '==', 'open').where('dueBy', '<=', horizon).limit(500).get();
    const due = snap.docs.map((d) => ({ id: d.id, ...d.data() }))
      .filter((a) => !a.remindedAt && !a.liveToken && a.dueBy > now.toISOString());
    let reminded = 0;
    for (const ask of due) {
      const planDoc = await this.plans.doc(ask.planId).get();
      if (!planDoc.exists || planDoc.data().status !== 'active') continue;
      const plan = { id: planDoc.id, ...planDoc.data() };
      // Claim it first so a retried run never sends twice
      try {
        await this.db.runTransaction(async (tx) => {
          const fresh = await tx.get(this.asks.doc(ask.id));
          if (!fresh.exists || fresh.data().remindedAt || fresh.data().status !== 'open') throw new Error('claimed');
          tx.update(this.asks.doc(ask.id), { remindedAt: now.toISOString() });
        });
      } catch (error) {
        continue;
      }
      await this.push(plan.parentId, {
        type: TYPES.askByKind[ask.kind] || TYPES.ask,
        title: `Still wondering · ${plan.ownerName || 'Your family'} asks`,
        body: ask.questionText,
        data: { planId: plan.id, askId: ask.id, questionText: ask.questionText, kind: ask.kind || 'mood', reminder: '1' }
      });
      reminded += 1;
    }
    return reminded;
  }
};

module.exports = { mixin: methods, contentState, attributesFor, ATTRIBUTES_TYPE, REMIND_AFTER_MS, START_TOKENS };
