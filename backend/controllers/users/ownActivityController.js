// backend/controllers/users/ownActivityController.js
// The profile's Activity tab: the signed-in user's own history and the
// month's summary. Owner only — there is no way to ask for someone else's.
const ownActivity = require('../../services/ownActivity');

// @route GET /api/users/me/activity?filter=all|checkins|places|moments|sent|social&cursor=<iso>&limit=30
exports.list = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit, 10) || 30;
    const page = await ownActivity.list({ userId: req.user.uid, filter: String(req.query.filter || 'all'), cursor: req.query.cursor || null, limit });
    res.json({ success: true, ...page });
  } catch (error) {
    console.error('[own-activity] list failed:', error);
    res.status(500).json({ success: false, message: 'Could not load your activity' });
  }
};

// @route GET /api/users/me/activity/summary?month=YYYY-MM&timezone=America/New_York
exports.summary = async (req, res) => {
  try {
    const summary = await ownActivity.summary({ userId: req.user.uid, month: req.query.month, timezone: String(req.query.timezone || 'UTC') });
    res.json({ success: true, summary });
  } catch (error) {
    console.error('[own-activity] summary failed:', error);
    res.status(500).json({ success: false, message: 'Could not load your month' });
  }
};
