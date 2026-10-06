// backend/controllers/widgets/eventController.js
// Events widget (Party Bus) — thin HTTP layer over services/eventService.
const eventService = require('../../services/eventService');
const extras = require('../../services/eventExtrasService');
const { sendServiceError } = require('../../utils/serviceError');

const handle = (label, fn) => async (req, res) => {
  try {
    return res.json({ success: true, ...(await fn(req)) });
  } catch (error) {
    return sendServiceError(res, error, { log: `🚌 ${label} failed`, fallbackMessage: 'Something went wrong with the event' });
  }
};

const uid = (req) => req.user.uid;

exports.listEvents = handle('listEvents', async (req) => ({ events: await eventService.listEvents(uid(req)) }));
exports.createEvent = handle('createEvent', async (req) => ({ event: await eventService.createEvent(uid(req), req.body || {}) }));
exports.getEvent = handle('getEvent', async (req) => eventService.getEvent(req.params.id, uid(req)));
exports.previewInvite = handle('previewInvite', async (req) => ({ preview: await eventService.previewByToken(req.params.token, uid(req)) }));
exports.join = handle('join', async (req) => eventService.joinByToken((req.body || {}).token, uid(req)));
exports.invite = handle('invite', async (req) => eventService.inviteConnections(req.params.id, uid(req), (req.body || {}).userIds));
exports.leave = handle('leave', async (req) => eventService.leaveEvent(req.params.id, uid(req)));
exports.removeMember = handle('removeMember', async (req) => eventService.removeMember(req.params.id, uid(req), req.params.memberId));
exports.update = handle('update', async (req) => ({ event: await eventService.updateEvent(req.params.id, uid(req), req.body || {}) }));
exports.resetLink = handle('resetLink', async (req) => ({ event: await eventService.resetInviteLink(req.params.id, uid(req)) }));
exports.end = handle('end', async (req) => eventService.endEvent(req.params.id, uid(req)));
exports.addPhotos = handle('addPhotos', async (req) => ({ photos: await eventService.addPhotos(req.params.id, uid(req), (req.body || {}).photos) }));
exports.deletePhoto = handle('deletePhoto', async (req) => eventService.deletePhoto(req.params.id, uid(req), req.params.photoId));
exports.likePhoto = handle('likePhoto', async (req) => ({ photo: await eventService.togglePhotoLike(req.params.id, uid(req), req.params.photoId) }));
exports.tagPlace = handle('tagPlace', async (req) => ({ place: await eventService.tagPlace(req.params.id, uid(req), req.body || {}) }));
exports.savePlace = handle('savePlace', async (req) => eventService.savePlaceToMyCircle(req.params.id, uid(req), req.params.placeId));

// Shout-out wall, song requests, photo challenges, roll call, recap
exports.listWall = handle('listWall', async (req) => extras.listWall(req.params.id, uid(req)));
exports.postToWall = handle('postToWall', async (req) => extras.postToWall(req.params.id, uid(req), req.body || {}));
exports.deleteWallPost = handle('deleteWallPost', async (req) => extras.deleteWallPost(req.params.id, uid(req), req.params.postId));
exports.reactToWallPost = handle('reactToWallPost', async (req) => extras.reactToWallPost(req.params.id, uid(req), req.params.postId, req.body || {}));
exports.listSongs = handle('listSongs', async (req) => extras.listSongs(req.params.id, uid(req)));
exports.requestSong = handle('requestSong', async (req) => extras.requestSong(req.params.id, uid(req), req.body || {}));
exports.voteSong = handle('voteSong', async (req) => extras.voteSong(req.params.id, uid(req), req.params.songId));
exports.markSongPlayed = handle('markSongPlayed', async (req) => extras.markSongPlayed(req.params.id, uid(req), req.params.songId, req.body || {}));
exports.deleteSong = handle('deleteSong', async (req) => extras.deleteSong(req.params.id, uid(req), req.params.songId));
exports.addChallenges = handle('addChallenges', async (req) => extras.addChallenges(req.params.id, uid(req), req.body || {}));
exports.removeChallenge = handle('removeChallenge', async (req) => extras.removeChallenge(req.params.id, uid(req), req.params.challengeId));
exports.startRollCall = handle('startRollCall', async (req) => extras.startRollCall(req.params.id, uid(req)));
exports.answerRollCall = handle('answerRollCall', async (req) => extras.answerRollCall(req.params.id, uid(req), req.body || {}));
exports.pingRollCall = handle('pingRollCall', async (req) => extras.pingMissing(req.params.id, uid(req), req.body || {}));
exports.closeRollCall = handle('closeRollCall', async (req) => extras.closeRollCall(req.params.id, uid(req)));
exports.recap = handle('recap', async (req) => extras.getRecap(req.params.id, uid(req)));

// Lock screen / Dynamic Island (Live Activity) push tokens
const live = require('../../services/eventLiveActivityService');
exports.registerLiveActivity = handle('registerLiveActivity', async (req) => live.register(req.params.id, uid(req), req.body || {}));
exports.unregisterLiveActivity = handle('unregisterLiveActivity', async (req) => live.unregister(req.params.id, uid(req)));
