// backend/controllers/widgets/clubController.js
// Clubs widget — thin HTTP layer over services/clubService.
const clubs = require('../../services/clubService');
const { sendServiceError } = require('../../utils/serviceError');

const handle = (label, fn) => async (req, res) => {
  try {
    return res.json({ success: true, ...(await fn(req)) });
  } catch (error) {
    return sendServiceError(res, error, { log: `👟 ${label} failed`, fallbackMessage: 'Something went wrong with the club' });
  }
};

const uid = (req) => req.user.uid;
const body = (req) => req.body || {};

exports.list = handle('list', async (req) => ({ clubs: await clubs.listClubs(uid(req)) }));
exports.create = handle('create', async (req) => ({ club: await clubs.createClub(uid(req), body(req)) }));
exports.previewInvite = handle('previewInvite', async (req) => ({ preview: await clubs.previewByToken(req.params.token, uid(req)) }));
exports.join = handle('join', async (req) => clubs.joinByToken(body(req).token, uid(req)));
exports.get = handle('get', async (req) => ({ club: await clubs.getClub(req.params.id, uid(req)) }));
exports.update = handle('update', async (req) => clubs.updateClub(req.params.id, uid(req), body(req)));
exports.end = handle('end', async (req) => clubs.endClub(req.params.id, uid(req)));
exports.leave = handle('leave', async (req) => clubs.leaveClub(req.params.id, uid(req)));
exports.mute = handle('mute', async (req) => clubs.setMuted(req.params.id, uid(req), body(req).muted === true));
exports.removeMember = handle('removeMember', async (req) => clubs.removeMember(req.params.id, uid(req), req.params.memberId));
exports.setRole = handle('setRole', async (req) => clubs.setRole(req.params.id, uid(req), req.params.memberId, body(req).role));
exports.resetLink = handle('resetLink', async (req) => clubs.resetInviteLink(req.params.id, uid(req)));
exports.invite = handle('invite', async (req) => clubs.inviteConnections(req.params.id, uid(req), body(req).userIds));

exports.addMeetup = handle('addMeetup', async (req) => clubs.addMeetup(req.params.id, uid(req), body(req)));
exports.updateMeetup = handle('updateMeetup', async (req) => clubs.updateMeetup(req.params.id, uid(req), req.params.meetupId, body(req)));
exports.deleteMeetup = handle('deleteMeetup', async (req) => clubs.deleteMeetup(req.params.id, uid(req), req.params.meetupId));
exports.addEvent = handle('addEvent', async (req) => clubs.addEvent(req.params.id, uid(req), body(req)));
exports.deleteEvent = handle('deleteEvent', async (req) => clubs.deleteEvent(req.params.id, uid(req), req.params.eventId));
exports.rsvp = handle('rsvp', async (req) => clubs.rsvp(req.params.id, uid(req), { key: body(req).key, status: body(req).status ?? null }));

exports.listPosts = handle('listPosts', async (req) => clubs.listPosts(req.params.id, uid(req), { kind: req.query.kind || 'board', before: req.query.before || null }));
exports.createPost = handle('createPost', async (req) => clubs.createPost(req.params.id, uid(req), body(req)));
exports.deletePost = handle('deletePost', async (req) => clubs.deletePost(req.params.id, uid(req), req.params.postId));
exports.react = handle('react', async (req) => clubs.react(req.params.id, uid(req), req.params.postId, body(req)));
exports.listReplies = handle('listReplies', async (req) => clubs.listReplies(req.params.id, uid(req), req.params.postId));
exports.addReply = handle('addReply', async (req) => clubs.addReply(req.params.id, uid(req), req.params.postId, body(req)));
exports.deleteReply = handle('deleteReply', async (req) => clubs.deleteReply(req.params.id, uid(req), req.params.postId, req.params.replyId));
