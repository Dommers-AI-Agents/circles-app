// backend/controllers/widgets/careCheckinController.js
// "How Are You?" check-ins. Handlers pass named fields to the service —
// never a body spread — and the service enforces who may do what.
const care = require('../../services/careCheckinService');

const fail = (res, error) => {
  if (error && error.status && error.code) {
    // `details` carries the plan a sibling should join instead of creating a
    // second one — the app turns that into "join theirs" rather than a dead end.
    return res.status(error.status).json({
      success: false, code: error.code, message: error.message, ...(error.details || {})
    });
  }
  console.error('[care] request failed:', error && error.message);
  return res.status(500).json({ success: false, code: 'care_failed', message: 'Something went wrong with check-ins.' });
};

exports.listPlans = async (req, res) => {
  try { res.json({ success: true, ...(await care.listPlans(req.user.uid)) }); } catch (e) { fail(res, e); }
};

exports.createPlan = async (req, res) => {
  const { parentId, times, questions } = req.body || {};
  try { res.status(201).json({ success: true, plan: await care.createPlan({ ownerId: req.user.uid, parentId, times, questions }) }); }
  catch (e) { fail(res, e); }
};

exports.updatePlan = async (req, res) => {
  const { times, questions, status } = req.body || {};
  try { res.json({ success: true, plan: await care.updatePlan({ userId: req.user.uid, planId: req.params.id, times, questions, status }) }); }
  catch (e) { fail(res, e); }
};

exports.endPlan = async (req, res) => {
  try { res.json({ success: true, ...(await care.endPlan({ userId: req.user.uid, planId: req.params.id })) }); }
  catch (e) { fail(res, e); }
};

exports.respond = async (req, res) => {
  const { accept, timezone } = req.body || {};
  try { res.json({ success: true, plan: await care.respondToInvite({ userId: req.user.uid, planId: req.params.id, accept: accept === true, timezone }) }); }
  catch (e) { fail(res, e); }
};

exports.listAsks = async (req, res) => {
  const planId = String(req.query.planId || '');
  const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 60));
  try { res.json({ success: true, asks: await care.listAsks({ userId: req.user.uid, planId, limit }) }); }
  catch (e) { fail(res, e); }
};

exports.answer = async (req, res) => {
  const { answer, note } = req.body || {};
  try { res.json({ success: true, ask: await care.answerAsk({ userId: req.user.uid, askId: req.params.id, answer, note }) }); }
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

exports.removeWatcher = async (req, res) => {
  try { res.json({ success: true, plan: await care.removeWatcher({ userId: req.user.uid, planId: req.params.id, watcherId: req.params.watcherId }) }); }
  catch (e) { fail(res, e); }
};
