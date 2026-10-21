// backend/controllers/venues/venueOrdersController.js — the store's side of
// order ahead (services/orders): the orders, accept/ready/picked up/decline,
// and the on/off + prep time setting. Behind requireVenueOwner (team) and
// requireOwnerPremium (Business).
const orders = require('../../services/orders/orderService');
const { sendServiceError } = require('../../utils/serviceError');

const fail = (res, error) => sendServiceError(res, error, { log: 'Venue order action failed', fallbackCode: 'order_failed', fallbackMessage: 'Couldn’t update that order. Try again.' });

// @route GET /api/rewards/venues/:venueId/orders?history=1
exports.list = async (req, res) => {
  try {
    const open = req.query.history !== '1';
    res.json({ success: true, data: await orders.forVenue(req.venue.venueId, { open }) });
  } catch (error) { fail(res, error); }
};

// @route POST /api/rewards/venues/:venueId/orders/:orderId/:action   (accept|ready|picked_up|decline)
//        body: { readyInMinutes? (accept), reason? (decline) }
exports.act = async (req, res) => {
  try {
    const { readyInMinutes, reason } = req.body || {};
    const data = await orders.storeAction(req.venue.venueId, req.params.orderId, req.params.action,
      { actorId: req.user.uid, readyInMinutes, reason });
    res.json({ success: true, data });
  } catch (error) { fail(res, error); }
};

// @route PUT /api/rewards/venues/:venueId/ordering   body: { enabled, leadMinutes, note? }
exports.saveSettings = async (req, res) => {
  try { res.json({ success: true, data: await orders.saveSettings(req.venue, req.body || {}) }); } catch (error) { fail(res, error); }
};
