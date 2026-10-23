// backend/controllers/widgets/dogParkController.js
// "Can I Pet Dat Dog" widget — thin HTTP layer over services/dogParkService.
const dogs = require('../../services/dogParkService');
const { sendServiceError } = require('../../utils/serviceError');
const { clientFromRequest } = require('../../utils/appVersion');

const handle = (label, fn) => async (req, res) => {
  try {
    return res.json({ success: true, ...(await fn(req)) });
  } catch (error) {
    return sendServiceError(res, error, { log: `🐶 ${label} failed`, fallbackMessage: 'Something went wrong in the Dog Park' });
  }
};

const uid = (req) => req.user.uid;
const body = (req) => req.body || {};

exports.me = handle('me', async (req) => dogs.me(uid(req), { client: clientFromRequest(req) }));
exports.join = handle('join', async (req) => dogs.join(uid(req)));
exports.leave = handle('leave', async (req) => dogs.leave(uid(req)));

exports.createDog = handle('createDog', async (req) => dogs.createDog(uid(req), body(req)));
exports.updateDog = handle('updateDog', async (req) => dogs.updateDog(uid(req), req.params.dogId, body(req)));
exports.deleteDog = handle('deleteDog', async (req) => dogs.deleteDog(uid(req), req.params.dogId));
exports.getDog = handle('getDog', async (req) => dogs.getDog(uid(req), req.params.dogId));

exports.feed = handle('feed', async (req) => dogs.feed(uid(req), { tab: req.query.tab || 'today', before: req.query.before || null }));
exports.getPost = handle('getPost', async (req) => dogs.getPost(uid(req), req.params.postId));
exports.createPost = handle('createPost', async (req) => dogs.createPhotoPost(uid(req), body(req)));
exports.startVideo = handle('startVideo', async (req) => dogs.startVideo(uid(req), body(req)));
exports.finishVideo = handle('finishVideo', async (req) => dogs.finishVideo(uid(req), req.params.videoId, body(req)));
exports.deletePost = handle('deletePost', async (req) => dogs.deletePost(uid(req), req.params.postId));
exports.pet = handle('pet', async (req) => dogs.togglePet(uid(req), req.params.postId));
exports.listComments = handle('listComments', async (req) => dogs.listComments(uid(req), req.params.postId));
exports.addComment = handle('addComment', async (req) => dogs.addComment(uid(req), req.params.postId, body(req)));
exports.deleteComment = handle('deleteComment', async (req) => dogs.deleteComment(uid(req), req.params.postId, req.params.commentId));
exports.report = handle('report', async (req) => dogs.reportPost(uid(req), req.params.postId, body(req)));
exports.block = handle('block', async (req) => dogs.blockAuthor(uid(req), req.params.userId));

exports.listDaily = handle('listDaily', async (req) => dogs.listDaily(uid(req), { before: req.query.before || null }));
exports.getDaily = handle('getDaily', async (req) => dogs.getDaily(uid(req), req.params.dailyId));
exports.updateSettings = handle('updateSettings', async (req) => dogs.updateSettings(uid(req), { enabled: body(req).enabled, times: body(req).times }));

// The core save's activity and pushes run after the reply, like Add Place's
exports.savePlace = async (req, res) => {
  try {
    const { afterResponse, ...saved } = await dogs.savePlace(req.user, body(req));
    res.json({ success: true, ...saved });
    if (afterResponse) await afterResponse().catch((err) => console.error('🐶 dog spot follow-up failed:', err.message));
  } catch (error) {
    sendServiceError(res, error, { log: '🐶 savePlace failed', fallbackMessage: 'Something went wrong in the Dog Park' });
  }
};

// Cloud Scheduler, every 15 minutes. Each person is gated on their own clock.
exports.runDailyDue = async (req, res) => {
  try {
    const result = await dogs.runDailyDue({
      userId: req.body && req.body.userId,
      force: req.body && req.body.force === true,
      dryRun: req.body && req.body.dryRun === true
    });
    console.log('🐶 daily dogs run:', JSON.stringify(result));
    res.json({ success: true, ...result });
  } catch (error) {
    sendServiceError(res, error, { log: '🐶 daily dogs run failed', fallbackMessage: 'Daily dogs failed' });
  }
};
