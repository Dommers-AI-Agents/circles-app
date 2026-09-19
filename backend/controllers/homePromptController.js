// backend/controllers/homePromptController.js
// Home "daily card": one server-picked card per visit (or none), plus the
// per-card ack the app posts on Skip / tap. State lives on the user doc — see
// services/homePromptService.js.
const homePromptService = require('../services/homePromptService');
const { HomePromptError } = require('../services/homePromptService');

function sendError(res, error, fallback) {
  if (error instanceof HomePromptError) {
    return res.status(error.status).json({ success: false, code: error.code, message: error.message });
  }
  console.error(`🃏 ${fallback}:`, error.message);
  return res.status(500).json({ success: false, message: fallback });
}

// @desc    The card to show on this home visit, if any
// @route   GET /api/home/prompt
// @access  Private
exports.getPrompt = async (req, res) => {
  try {
    // The app's build, when it sends one, so a card about a new feature can be
    // held back from builds that do not have it. Absent on older clients, and
    // absence never excludes anyone.
    const appVersion = req.get('X-App-Version') || null;
    const card = await homePromptService.pick(req.user.uid, {}, { appVersion });
    res.status(200).json({ success: true, card });
  } catch (error) {
    // Never fail the home screen over a card: report "nothing today".
    console.error('🃏 home prompt pick failed:', error.message);
    res.status(200).json({ success: true, card: null });
  }
};

// @desc    Record what the user did with a card (skipped | acted | shown)
// @route   POST /api/home/prompt/:key/ack
// @access  Private
exports.ackPrompt = async (req, res) => {
  try {
    const action = req.body && req.body.action;
    const ack = await homePromptService.ack(req.user.uid, req.params.key, action);
    res.status(200).json({ success: true, ack });
  } catch (error) {
    sendError(res, error, 'Failed to record card response');
  }
};
