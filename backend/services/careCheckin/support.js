// services/careCheckin/support.js — family support on the parent's answers
// (Wes 2026-10-07): one-tap reactions on any answer, and on a heads-up
// answer a response ("I'll call her", "I'm on my way", "Got it") so the
// parent hears someone's coming and the rest of the family sees it's
// handled. Methods are mixed into CareCheckinService; the copy is pure.
const { FieldPath } = require('firebase-admin/firestore');
const { CareError, nowIso } = require('./shared');

const REACTIONS = {
  love: { emoji: '❤️', label: 'Love you' },
  glad: { emoji: '🙏', label: 'Glad to hear it' },
  proud: { emoji: '💪', label: 'Proud of you' },
  thinking: { emoji: '🤗', label: 'Thinking of you' }
};

const RESPONSES = {
  calling: { label: "I'll call", parentLine: (n) => `${n} is going to call you soon`, teamLine: (n, p) => `${n} is calling ${p}` },
  on_my_way: { label: "I'm on my way", parentLine: (n) => `${n} is on the way`, teamLine: (n, p) => `${n} is on the way to ${p}` },
  got_it: { label: 'Got it', parentLine: null, teamLine: (n) => `${n} has it` }
};

const PUSH_REACTION = 'care_reaction';
const PUSH_RESPONSE = 'care_alert_response';
const PUSH_HANDLED = 'care_alert_handled';

/** Pure: the support on one answer, as every viewer sees it (oldest first). */
function presentSupport(ask) {
  const byTime = (a, b) => String(a.at || '').localeCompare(String(b.at || ''));
  const reactions = Object.entries(ask.reactions || {})
    .filter(([, r]) => r && REACTIONS[r.kind])
    .map(([userId, r]) => ({ userId, name: r.name || 'Family', kind: r.kind, at: r.at || null }))
    .sort(byTime);
  const responses = Object.entries(ask.responses || {})
    .filter(([, r]) => r && RESPONSES[r.action])
    .map(([userId, r]) => ({ userId, name: r.name || 'Family', action: r.action, at: r.at || null }))
    .sort(byTime);
  return { reactions, responses };
}

/** Pure: the push wording. */
const reactionPush = (name, kind, ask) => ({
  title: `${REACTIONS[kind].emoji} ${name}: ${REACTIONS[kind].label}`,
  body: `About your answer “${ask.answerText || ''}”${ask.short ? ` (${ask.short})` : ''}`.replace(' “”', '')
});

function memberName(plan, userId) {
  if (userId === plan.ownerId) return plan.ownerName || 'Family';
  const w = (plan.watchers || []).find((x) => x.userId === userId);
  return (w && w.name) || 'Family';
}

module.exports = {
  REACTIONS, RESPONSES, PUSH_REACTION, PUSH_RESPONSE, PUSH_HANDLED, presentSupport, reactionPush,

  mixin: {
    /** One reaction per person per answer; `kind: null` takes it back. */
    async reactToAsk({ userId, askId, kind }) {
      const doc = await this.asks.doc(String(askId)).get();
      if (!doc.exists) throw new CareError(404, 'no_ask', 'That answer is gone.');
      const ask = { id: doc.id, ...doc.data() };
      const plan = await this.requirePlan(ask.planId);
      const role = this.constructor.roleOf(plan, userId);
      if (!['owner', 'watcher'].includes(role)) throw new CareError(403, 'not_family', 'Only family on this check-in can react.');
      if (ask.status !== 'answered') throw new CareError(400, 'not_answered', 'React once there is an answer.');
      if (kind !== null && !REACTIONS[kind]) throw new CareError(400, 'bad_reaction', 'Unknown reaction.');

      const before = (ask.reactions || {})[userId];
      const name = memberName(plan, userId);
      const value = kind === null ? require('firebase-admin/firestore').FieldValue.delete() : { kind, name, at: nowIso() };
      await this.asks.doc(ask.id).update(new FieldPath('reactions', userId), value);
      const reactions = { ...(ask.reactions || {}) };
      if (kind === null) delete reactions[userId]; else reactions[userId] = value;

      // The parent hears a person's FIRST reaction to an answer (changing it
      // later doesn't ping again), unless they hushed reactions
      if (kind !== null && !before && plan.reactionPushesOff !== true) {
        const { title, body } = reactionPush(name, kind, ask);
        this.notify(plan.parentId, { type: PUSH_REACTION, title, body, data: { planId: plan.id, askId: ask.id } });
      }
      return this.presentAsk({ ...ask, reactions });
    },

    /** A heads-up answer: someone says they've got it. */
    async respondToAlert({ userId, askId, action }) {
      const doc = await this.asks.doc(String(askId)).get();
      if (!doc.exists) throw new CareError(404, 'no_ask', 'That answer is gone.');
      const ask = { id: doc.id, ...doc.data() };
      const plan = await this.requirePlan(ask.planId);
      const role = this.constructor.roleOf(plan, userId);
      if (!['owner', 'watcher'].includes(role)) throw new CareError(403, 'not_family', 'Only family on this check-in can respond.');
      if (ask.alert !== true) throw new CareError(400, 'not_alert', 'Responses are for heads-up answers.');
      if (!RESPONSES[action]) throw new CareError(400, 'bad_response', 'Unknown response.');

      const before = (ask.responses || {})[userId];
      const name = memberName(plan, userId);
      const value = { action, name, at: nowIso() };
      await this.asks.doc(ask.id).update(new FieldPath('responses', userId), value);
      const responses = { ...(ask.responses || {}), [userId]: value };

      if (!before || before.action !== action) {
        const spec = RESPONSES[action];
        const parentName = plan.parentName || 'them';
        if (spec.parentLine) {
          this.notify(plan.parentId, {
            type: PUSH_RESPONSE, title: spec.parentLine(name), body: 'Your family saw your answer.', data: { planId: plan.id, askId: ask.id }
          });
        }
        for (const id of this.constructor.careTeam(plan).filter((m) => m !== userId)) {
          this.notify(id, {
            type: PUSH_HANDLED, title: spec.teamLine(name, parentName),
            body: `About “${ask.answerText || ''}”`, data: { planId: plan.id, askId: ask.id }
          });
        }
      }
      return this.presentAsk({ ...ask, responses });
    },

    /** The parent's own switch: no pushes when family reacts (they still see them). */
    async setReactionPushes({ userId, planId, on }) {
      const plan = await this.requirePlan(planId);
      if (plan.parentId !== userId) throw new CareError(403, 'not_parent', 'Only the person being checked on can change this.');
      await this.plans.doc(plan.id).update({ reactionPushesOff: on !== true, updatedAt: nowIso() });
      return { reactionPushesOff: on !== true };
    }
  }
};
