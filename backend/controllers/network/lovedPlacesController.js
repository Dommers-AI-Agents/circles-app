// backend/controllers/network/lovedPlacesController.js
// My Network → Discover: places two or more of your connections saved.
const lovedPlaces = require('../../services/networkLovedPlaces');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/network/loved-places?limit=
exports.list = async (req, res) => {
  try {
    const limit = Math.max(1, Math.min(60, parseInt(req.query.limit, 10) || 60));
    res.json({ success: true, places: await lovedPlaces.forViewer(req.user.uid, { limit }) });
  } catch (error) {
    sendServiceError(res, error, { log: '[loved-places] failed', fallbackMessage: 'Could not load places your people love' });
  }
};
