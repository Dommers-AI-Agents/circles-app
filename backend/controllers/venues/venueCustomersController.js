// controllers/venues/venueCustomersController.js
// The store team's Customers list and "Remove from rewards" (Wes,
// 2026-11-02) — services/storeCustomers.js. Behind requireVenueOwner.
const storeCustomers = require('../../services/storeCustomers');
const { sendServiceError } = require('../../utils/serviceError');

// GET /api/rewards/venues/:venueId/customers
exports.listCustomers = async (req, res) => {
  try {
    const customers = await storeCustomers.listCustomers(req.venue);
    res.json({ success: true, data: { customers } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ listCustomers failed', fallbackMessage: 'Failed to load customers' });
  }
};

// POST /api/rewards/venues/:venueId/customers/:userId/remove
exports.removeCustomer = async (req, res) => {
  try {
    await storeCustomers.removeCustomer(req.venue, req.params.userId);
    res.json({ success: true, data: { removed: true } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ removeCustomer failed', fallbackMessage: 'Could not remove them from rewards' });
  }
};

// POST /api/rewards/venues/:venueId/customers/:userId/restore
exports.restoreCustomer = async (req, res) => {
  try {
    await storeCustomers.restoreCustomer(req.venue, req.params.userId);
    res.json({ success: true, data: { removed: false } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ restoreCustomer failed', fallbackMessage: 'Could not restore them' });
  }
};
