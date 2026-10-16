// backend/controllers/widgets/workoutFeedController.js
const feed = require('../../services/workoutFeedService');
const { trackWorkoutShared } = require('../../services/activity/social');

const { sendServiceError } = require('../../utils/serviceError');
const fail = (res, error) => sendServiceError(res, error, {
  log: '[workout-feed] request failed', fallbackCode: 'feed_failed', fallbackMessage: 'Something went wrong sharing the workout.'
});

exports.share = async (req, res) => {
  const { summary, audience, audienceListId } = req.body || {};
  const userId = req.user.uid;
  try {
    const result = await feed.share({
      userId, summary, audience, audienceListId,
      onFirstShare: (post) => trackWorkoutShared(userId, post)
    });
    res.status(201).json({ success: true, ...result });
  } catch (e) { fail(res, e); }
};

exports.link = async (req, res) => {
  try {
    res.status(201).json({ success: true, ...(await feed.createLink({ userId: req.user.uid, summary: (req.body || {}).summary })) });
  } catch (e) { fail(res, e); }
};

exports.post = async (req, res) => {
  try { res.json({ success: true, post: await feed.getPost(req.params.postId, req.user.uid) }); } catch (e) { fail(res, e); }
};

exports.feed = async (req, res) => {
  try { res.json({ success: true, posts: await feed.feed(req.user.uid) }); } catch (e) { fail(res, e); }
};

// The person's own history, sent by their phone (enabled: false removes it)
exports.syncHistory = async (req, res) => {
  const { enabled, workouts } = req.body || {};
  try { res.json({ success: true, ...(await feed.syncHistory({ userId: req.user.uid, enabled: enabled === true, workouts })) }); } catch (e) { fail(res, e); }
};

// Someone's history, for their Inner Circle
exports.history = async (req, res) => {
  try { res.json({ success: true, history: await feed.history(req.params.userId, req.user.uid) }); } catch (e) { fail(res, e); }
};
