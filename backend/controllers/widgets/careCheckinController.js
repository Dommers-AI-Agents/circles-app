// backend/controllers/widgets/careCheckinController.js
// "How Are You?" check-ins. Handlers pass named fields to the service —
// never a body spread — and the service enforces who may do what.
const care = require('../../services/careCheckinService');
const { clientFromRequest } = require('../../utils/appVersion');

const { sendServiceError } = require('../../utils/serviceError');
const fail = (res, error) => sendServiceError(res, error, {
  log: '[care] request failed', fallbackCode: 'care_failed', fallbackMessage: 'Something went wrong with check-ins.'
});

exports.listPlans = async (req, res) => {
  try { res.json({ success: true, ...(await care.listPlans(req.user.uid)) }); } catch (e) { fail(res, e); }
};

exports.createPlan = async (req, res) => {
  const { parentId, times, questions, profile } = req.body || {};
  try { res.status(201).json({ success: true, plan: await care.createPlan({ ownerId: req.user.uid, parentId, times, questions, profile }) }); }
  catch (e) { fail(res, e); }
};

exports.updatePlan = async (req, res) => {
  const { times, questions, status, profile, mutedQuestionIds } = req.body || {};
  try { res.json({ success: true, plan: await care.updatePlan({ userId: req.user.uid, planId: req.params.id, times, questions, status, profile, mutedQuestionIds }) }); }
  catch (e) { fail(res, e); }
};

exports.endPlan = async (req, res) => {
  try { res.json({ success: true, ...(await care.endPlan({ userId: req.user.uid, planId: req.params.id })) }); }
  catch (e) { fail(res, e); }
};

exports.respond = async (req, res) => {
  const { accept, timezone } = req.body || {};
  try { res.json({ success: true, plan: await care.respondToInvite({ userId: req.user.uid, planId: req.params.id, accept: accept === true, timezone, client: clientFromRequest(req) }) }); }
  catch (e) { fail(res, e); }
};

// The owner nudges a parent who hasn't answered the invitation.
exports.resendInvite = async (req, res) => {
  try { res.json({ success: true, ...(await care.resendInvite({ userId: req.user.uid, planId: req.params.id })) }); }
  catch (e) { fail(res, e); }
};

exports.listAsks = async (req, res) => {
  const planId = String(req.query.planId || '');
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 60));
  const before = req.query.before ? String(req.query.before) : null;
  try { res.json({ success: true, ...(await care.listAsks({ userId: req.user.uid, planId, limit, before })) }); }
  catch (e) { fail(res, e); }
};

// `answer` is a choice key; `value` a 0–10 number or typed words. Which one
// applies is decided by the question's kind, in the service.
exports.answer = async (req, res) => {
  const { answer, value, note } = req.body || {};
  try { res.json({ success: true, ask: await care.answerAsk({ userId: req.user.uid, askId: req.params.id, answer, value, note, client: clientFromRequest(req) }) }); }
  catch (e) { fail(res, e); }
};

// @route POST /api/tasks/care-checkins (Cloud Scheduler, every 15 minutes)
exports.runDue = async (req, res) => {
  try {
    const summary = await care.runDue();
    console.log(`[care] run: ${JSON.stringify(summary)}`);
    res.json({ success: true, ...summary });
  } catch (error) {
    console.error('[care] run failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

// A sibling asks to join, or the owner invites one. Either way the parent decides.
exports.requestWatcher = async (req, res) => {
  const { watcherId } = req.body || {};
  try { res.status(201).json({ success: true, plan: await care.requestWatcher({ userId: req.user.uid, planId: req.params.id, watcherId }) }); }
  catch (e) { fail(res, e); }
};

exports.respondToWatcher = async (req, res) => {
  const { accept } = req.body || {};
  try { res.json({ success: true, plan: await care.respondToWatcher({ userId: req.user.uid, planId: req.params.id, watcherId: req.params.watcherId, accept: accept === true }) }); }
  catch (e) { fail(res, e); }
};

exports.resendWatcherInvite = async (req, res) => {
  try { res.json({ success: true, ...(await care.resendWatcherInvite({ userId: req.user.uid, planId: req.params.id, watcherId: req.params.watcherId })) }); }
  catch (e) { fail(res, e); }
};

exports.removeWatcher = async (req, res) => {
  try { res.json({ success: true, plan: await care.removeWatcher({ userId: req.user.uid, planId: req.params.id, watcherId: req.params.watcherId }) }); }
  catch (e) { fail(res, e); }
};

// Join the check-in someone else already set up on this parent.
exports.joinForParent = async (req, res) => {
  const { parentId } = req.body || {};
  try { res.status(201).json({ success: true, plan: await care.requestWatcherForParent({ userId: req.user.uid, parentId }) }); }
  catch (e) { fail(res, e); }
};

// Family support (2026-10-07): react to an answer; respond to a heads-up;
// the parent's switch for reaction pushes.
exports.react = async (req, res) => {
  try {
    const kind = (req.body || {}).kind === null ? null : String((req.body || {}).kind || '');
    res.json({ success: true, ask: await care.reactToAsk({ userId: req.user.uid, askId: req.params.id, kind }) });
  } catch (error) { fail(res, error); }
};
exports.respondToAlert = async (req, res) => {
  try {
    res.json({ success: true, ask: await care.respondToAlert({ userId: req.user.uid, askId: req.params.id, action: String((req.body || {}).action || '') }) });
  } catch (error) { fail(res, error); }
};
exports.setReactionPushes = async (req, res) => {
  try {
    res.json({ success: true, ...(await care.setReactionPushes({ userId: req.user.uid, planId: req.params.id, on: (req.body || {}).on === true })) });
  } catch (error) { fail(res, error); }
};
