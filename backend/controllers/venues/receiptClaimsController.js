// controllers/venues/receiptClaimsController.js
// Points for delivery orders: the customer sends a receipt, the store's team
// answers (or it pays right away in Automatic mode). Rules in
// services/receiptClaims.
const receiptClaims = require('../../services/receiptClaims');
const { sendServiceError } = require('../../utils/serviceError');

const fail = (res, error, log) => sendServiceError(res, error, {
  log, fallbackCode: 'RECEIPT_FAILED', fallbackMessage: 'Something went wrong with that receipt'
});

// @route POST /api/rewards/venues/:venueId/receipts   { image: base64, receipt: { text, storeLine, orderDate, orderNumber, deliveryApp, total } }
exports.submit = async (req, res) => {
  try {
    res.status(201).json({ success: true, data: await receiptClaims.submit(req.user.uid, req.params.venueId, req.body || {}) });
  } catch (error) { fail(res, error, 'Receipt submit'); }
};

// @route GET /api/rewards/venues/:venueId/receipts?status=pending
exports.list = async (req, res) => {
  try {
    const status = ['pending', 'approved', 'declined', 'expired'].includes(req.query.status) ? req.query.status : 'pending';
    res.json({ success: true, data: { receipts: await receiptClaims.listForVenue(req.venue, { status }), mode: receiptClaims.mode(req.venue) } });
  } catch (error) { fail(res, error, 'Receipt list'); }
};

// @route POST /api/rewards/venues/:venueId/receipts/:claimId/approve
exports.approve = async (req, res) => {
  try {
    res.json({ success: true, data: await receiptClaims.approve(req.venue, req.params.claimId, req.user.uid) });
  } catch (error) { fail(res, error, 'Receipt approve'); }
};

// @route POST /api/rewards/venues/:venueId/receipts/:claimId/decline
exports.decline = async (req, res) => {
  try {
    res.json({ success: true, data: await receiptClaims.decline(req.venue, req.params.claimId, req.user.uid) });
  } catch (error) { fail(res, error, 'Receipt decline'); }
};

// @route PUT /api/rewards/venues/:venueId/delivery-receipts   { mode: off|approve|auto }
exports.setMode = async (req, res) => {
  try {
    res.json({ success: true, data: await receiptClaims.setMode(req.venue, (req.body || {}).mode) });
  } catch (error) { fail(res, error, 'Receipt setting'); }
};
