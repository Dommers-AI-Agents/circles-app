// backend/controllers/orders/orderController.js — the customer's side of
// order ahead (services/orders): place, see, cancel. Pay at pickup.
const orders = require('../../services/orders/orderService');
const { sendServiceError } = require('../../utils/serviceError');

const fail = (res, error) => sendServiceError(res, error, { log: 'Order failed', fallbackCode: 'order_failed', fallbackMessage: 'Something went wrong with that order. Try again.' });

// @route POST /api/orders   body: { venueId, items: [{ itemId, qty, note? }], note?, pickup: 'asap' | ISO }
exports.place = async (req, res) => {
  try {
    const { venueId, items, note, pickup } = req.body || {};
    res.json({ success: true, data: await orders.place({ customerId: req.user.uid, venueId, items, note, pickup }) });
  } catch (error) { fail(res, error); }
};

// @route GET /api/orders/mine
exports.mine = async (req, res) => {
  try { res.json({ success: true, data: await orders.mine(req.user.uid) }); } catch (error) { fail(res, error); }
};

// @route GET /api/orders/:orderId   (the customer or the store's team)
exports.get = async (req, res) => {
  try { res.json({ success: true, data: await orders.get(req.params.orderId, req.user.uid) }); } catch (error) { fail(res, error); }
};

// @route POST /api/orders/:orderId/cancel   (before the store accepts)
exports.cancel = async (req, res) => {
  try { res.json({ success: true, data: await orders.cancel(req.params.orderId, req.user.uid) }); } catch (error) { fail(res, error); }
};
