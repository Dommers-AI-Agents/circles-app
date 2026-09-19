// backend/controllers/widgets/workoutFeedController.js
const feed = require('../../services/workoutFeedService');

const fail = (res, error) => {
  if (error && error.status && error.code) {
    return res.status(error.status).json({ success: false, code: error.code, message: error.message });
  }
  console.error('[workout-feed] request failed:', error && error.message);
  return res.status(500).json({ success: false, code: 'feed_failed', message: 'Something went wrong sharing the workout.' });
};

exports.share = async (req, res) => {
  const { summary } = req.body || {};
  try { res.status(201).json({ success: true, ...(await feed.share({ userId: req.user.uid, summary })) }); } catch (e) { fail(res, e); }
};

exports.feed = async (req, res) => {
  try { res.json({ success: true, posts: await feed.feed(req.user.uid) }); } catch (e) { fail(res, e); }
};
