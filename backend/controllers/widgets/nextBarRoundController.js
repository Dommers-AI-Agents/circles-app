// backend/controllers/widgets/nextBarRoundController.js
// NextBar voting rounds: thin HTTP layer over services/nextBarRoundService.
// All validation, permission checks, and the vote/close transaction live in
// the service; this file only maps RoundError → status/code.
const nextBarRoundService = require('../../services/nextBarRoundService');
const { RoundError } = require('../../services/nextBarRoundService');

function sendError(res, error, fallback) {
  if (error instanceof RoundError) {
    return res.status(error.status).json({
      success: false,
      code: error.code,
      message: error.message,
      ...(error.userId ? { userId: error.userId } : {})
    });
  }
  console.error(`🍸 ${fallback}:`, error.message);
  return res.status(500).json({ success: false, message: fallback });
}

// @desc    Start a bar vote among tagged connections
// @route   POST /api/widgets/nextbar/rounds
// @access  Private
exports.createRound = async (req, res) => {
  try {
    const { participantIds, options, expiresInMinutes } = req.body || {};
    const round = await nextBarRoundService.createRound(req.user, { participantIds, options, expiresInMinutes });
    res.status(201).json({ success: true, round });
  } catch (error) {
    sendError(res, error, 'Failed to start the round');
  }
};

// @desc    Rounds the caller is part of (newest first; expired ones closed lazily)
// @route   GET /api/widgets/nextbar/rounds
// @access  Private
exports.listRounds = async (req, res) => {
  try {
    const rounds = await nextBarRoundService.listRounds(req.user.uid);
    res.status(200).json({ success: true, rounds });
  } catch (error) {
    sendError(res, error, 'Failed to load rounds');
  }
};

// @desc    One round (participants only)
// @route   GET /api/widgets/nextbar/rounds/:id
// @access  Private
exports.getRound = async (req, res) => {
  try {
    const round = await nextBarRoundService.getRound(req.user.uid, req.params.id);
    res.status(200).json({ success: true, round });
  } catch (error) {
    sendError(res, error, 'Failed to load the round');
  }
};

// @desc    Cast (or change) a vote; the last vote closes the round
// @route   POST /api/widgets/nextbar/rounds/:id/vote
// @access  Private
exports.vote = async (req, res) => {
  try {
    const { placeId } = req.body || {};
    const round = await nextBarRoundService.vote(req.user.uid, req.params.id, placeId);
    res.status(200).json({ success: true, round });
  } catch (error) {
    sendError(res, error, 'Failed to record the vote');
  }
};

// @desc    Host ends the round early
// @route   POST /api/widgets/nextbar/rounds/:id/close
// @access  Private
exports.closeRound = async (req, res) => {
  try {
    const round = await nextBarRoundService.closeRound(req.user.uid, req.params.id);
    res.status(200).json({ success: true, round });
  } catch (error) {
    sendError(res, error, 'Failed to end the round');
  }
};
