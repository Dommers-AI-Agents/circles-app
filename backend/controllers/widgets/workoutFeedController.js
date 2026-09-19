// backend/controllers/widgets/workoutFeedController.js
const feed = require('../../services/workoutFeedService');

const { sendServiceError } = require('../../utils/serviceError');
const fail = (res, error) => sendServiceError(res, error, {
  log: '[workout-feed] request failed', fallbackCode: 'feed_failed', fallbackMessage: 'Something went wrong sharing the workout.'
});

exports.share = async (req, res) => {
  const { summary } = req.body || {};
  try { res.status(201).json({ success: true, ...(await feed.share({ userId: req.user.uid, summary })) }); } catch (e) { fail(res, e); }
};

exports.feed = async (req, res) => {
  try { res.json({ success: true, posts: await feed.feed(req.user.uid) }); } catch (e) { fail(res, e); }
};
