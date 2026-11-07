// backend/controllers/network/lovedPlacesController.js
// My Network → Discover: places two or more of your connections saved.
const lovedPlaces = require('../../services/networkLovedPlaces');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/network/loved-places?limit=&fallback=community
// fallback=community: an app that can title it gets places saved near you
// when your people have none (scope says which)
exports.list = async (req, res) => {
  try {
    const limit = Math.max(1, Math.min(60, parseInt(req.query.limit, 10) || 60));
    const fallback = req.query.fallback === 'community' ? 'community' : null;
    const { scope, places } = await lovedPlaces.pageForViewer(req.user.uid, { limit, fallback });
    res.json({ success: true, scope, places });
  } catch (error) {
    sendServiceError(res, error, { log: '[loved-places] failed', fallbackMessage: 'Could not load places your people love' });
  }
};
