// backend/controllers/network/lovedPlacesController.js
// My Network → Discover: places two or more of your connections saved.
const lovedPlaces = require('../../services/networkLovedPlaces');

// @route GET /api/network/loved-places?limit=
exports.list = async (req, res) => {
  try {
    const limit = Math.max(1, Math.min(60, parseInt(req.query.limit, 10) || 60));
    res.json({ success: true, places: await lovedPlaces.forViewer(req.user.uid, { limit }) });
  } catch (error) {
    console.error('[loved-places] failed:', error);
    res.status(500).json({ success: false, message: 'Could not load places your people love' });
  }
};
