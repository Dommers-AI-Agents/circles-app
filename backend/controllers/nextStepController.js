// The app's next-step ranking for this person (phase 4 of "never a dead end")
const nextStepService = require('../services/nextStepService');
const { sendServiceError } = require('../utils/serviceError');

// GET /api/next-steps → { order, boost, avoid }
exports.getNextSteps = async (req, res) => {
  try {
    const ranked = nextStepService.rank(await nextStepService.signals(req.user.uid));
    res.json({ success: true, data: ranked });
  } catch (error) {
    sendServiceError(res, error, { log: 'next-steps failed', fallbackMessage: 'Something went wrong.' });
  }
};

// POST /api/next-steps/events { events: [{ step, surface, kind: shown|tapped }] }
exports.recordEvents = async (req, res) => {
  try {
    const recorded = await nextStepService.record(req.user.uid, req.body && req.body.events);
    res.json({ success: true, data: { recorded } });
  } catch (error) {
    sendServiceError(res, error, { log: 'next-steps events failed', fallbackMessage: 'Something went wrong.' });
  }
};
