// backend/controllers/users/contributionsController.js
// The screen a milestone / top-contributor push opens: your last 30 days of
// adding places. Owner only.
const contributionStats = require('../../services/contributionStats');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/users/me/contributions
exports.mine = async (req, res) => {
  try {
    res.json({ success: true, data: await contributionStats.forUser(req.user.uid) });
  } catch (error) {
    sendServiceError(res, error, { log: '[contributions] failed', fallbackMessage: 'Could not load your month' });
  }
};
