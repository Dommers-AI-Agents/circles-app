// backend/controllers/users/contributionsController.js
// The screen a milestone / top-contributor push opens: your last 30 days of
// adding places. Owner only.
const contributionStats = require('../../services/contributionStats');

// @route GET /api/users/me/contributions
exports.mine = async (req, res) => {
  try {
    res.json({ success: true, data: await contributionStats.forUser(req.user.uid) });
  } catch (error) {
    console.error('[contributions] failed:', error);
    res.status(500).json({ success: false, message: 'Could not load your month' });
  }
};
