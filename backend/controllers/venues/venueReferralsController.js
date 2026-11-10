// controllers/venues/venueReferralsController.js
// Manage Store → Bring a friend (2026-11-09): the store's referral points and
// how many friends were brought in. Business only; rules in services/storeReferrals.
const referrals = require('../../services/storeReferrals');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/rewards/venues/:venueId/referrals
exports.get = async (req, res) => {
  try {
    res.json({ success: true, data: { settings: referrals.settingsOf(req.venue), stats: await referrals.stats(req.venue) } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to load referrals', fallbackMessage: 'Failed to load referrals' });
  }
};

// @route PUT /api/rewards/venues/:venueId/referrals   body: { enabled, referrerPoints, friendPoints }
exports.update = async (req, res) => {
  try {
    res.json({ success: true, data: { settings: await referrals.saveSettings(req.venue, req.body || {}) } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to save referrals', fallbackMessage: 'Failed to save referrals' });
  }
};
