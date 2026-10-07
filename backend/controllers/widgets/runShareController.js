// backend/controllers/widgets/runShareController.js
// FavRun, shared: watch live, cheers, post to activity — thin HTTP layer
// over services/runShareService.
const runs = require('../../services/runShareService');
const { sendServiceError } = require('../../utils/serviceError');

const handle = (label, fn) => async (req, res) => {
  try {
    return res.json({ success: true, ...(await fn(req)) });
  } catch (error) {
    return sendServiceError(res, error, { log: `🏃 ${label} failed`, fallbackMessage: 'Something went wrong with the run' });
  }
};
const uid = (req) => req.user.uid;

/** Whether the viewer is in a posted run's feed audience (same gate as the feed row). */
const feedAudienceCheck = (viewerId) => async (run) => {
  const { passesItemGates } = require('../../services/activityPrivacy');
  const { buildViewerContext } = require('../../services/viewerContext');
  const ctx = await buildViewerContext(viewerId);
  return passesItemGates({ type: 'run_shared', actorId: run.ownerId,
    metadata: { runAudience: run.postAudience, audienceListId: run.postAudienceListId } }, viewerId, ctx);
};

exports.startLive = handle('startLive', async (req) => runs.startLive(uid(req), req.body || {}));
exports.invite = handle('invite', async (req) => runs.invite(req.params.id, uid(req), req.body || {}));
exports.watch = handle('watch', async (req) => runs.watch(req.params.id, uid(req), req.body || {}));
exports.join = handle('join', async (req) => runs.watch(null, uid(req), { token: (req.body || {}).token }));
exports.getRun = handle('getRun', async (req) => runs.getPostedRun(req.params.id, uid(req), feedAudienceCheck(uid(req))));
exports.progress = handle('progress', async (req) => runs.progress(req.params.id, uid(req), req.body || {}));
exports.finish = handle('finish', async (req) => runs.finish(req.params.id, uid(req), req.body || {}));
exports.cancel = handle('cancel', async (req) => runs.cancel(req.params.id, uid(req)));
exports.cheer = handle('cheer', async (req) => runs.cheer(req.params.id, uid(req), req.body || {}));
exports.watching = handle('watching', async (req) => runs.listWatching(uid(req)));
exports.post = handle('post', async (req) => runs.postToActivity(uid(req), req.body || {}));
exports.coachVoice = handle('coachVoice', async (req) => require('../../services/coachVoiceService').speak((req.body || {}).text));
