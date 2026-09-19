// backend/controllers/widgets/careCheckinController.js
// "How Are You?" check-ins. Handlers pass named fields to the service —
// never a body spread — and the service enforces who may do what.
const care = require('../../services/careCheckinService');

const fail = (res, error) => {
  if (error && error.status && error.code) {
    return res.status(error.status).json({ success: false, code: error.code, message: error.message });
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
