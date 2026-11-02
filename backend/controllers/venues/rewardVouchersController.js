// controllers/venues/rewardVouchersController.js
// Reward tickets (2026-11-01): the customer's open and recent tickets, the
// staff "Given" tap on the customer's phone, and the store team's list.
const vouchers = require('../../services/rewardVoucherService');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/rewards/vouchers   (customer)
exports.listMine = async (req, res) => {
  try {
    res.json({ success: true, data: await vouchers.listForUser(req.user.uid) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Reward tickets', fallbackCode: 'VOUCHERS_FAILED', fallbackMessage: 'Couldn’t load your rewards' });
  }
};

// @route POST /api/rewards/vouchers/:voucherId/given   (customer's phone, staff tap)
exports.markGiven = async (req, res) => {
  try {
    res.json({ success: true, data: await vouchers.markGiven(req.user.uid, req.params.voucherId) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Reward given', fallbackCode: 'VOUCHER_FAILED', fallbackMessage: 'Couldn’t mark it given. Try again.' });
  }
};

// @route GET /api/rewards/venues/:venueId/vouchers   (store team)
exports.listForVenue = async (req, res) => {
  try {
    res.json({ success: true, data: { vouchers: await vouchers.listForVenue(req.venue.venueId) } });
  } catch (error) {
    sendServiceError(res, error, { log: 'Store rewards used', fallbackCode: 'VOUCHERS_FAILED', fallbackMessage: 'Couldn’t load rewards used' });
  }
};
