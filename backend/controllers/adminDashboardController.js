// backend/controllers/adminDashboardController.js
//
// Read-only JSON for the admin dashboard (public/admin/index.html).
// Mounted behind protect + super-user in routes/adminDashboardRoutes.js.
const analytics = require('../services/adminAnalytics');
const { serializeDates } = require('../utils/wireDates');

const handle = (fn) => async (req, res) => {
  try {
    const body = await fn(req);
    if (body === null) return res.status(404).json({ success: false, message: 'Not found' });
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, ...serializeDates(body) });
  } catch (error) {
    console.error('📊 Admin dashboard error:', error);
    return res.status(500).json({ success: false, message: 'Could not load the dashboard data' });
  }
};

exports.me = handle(async (req) => ({ admin: { id: req.user.uid, name: req.user.displayName || req.user.email || 'Admin' } }));
exports.overview = handle((req) => analytics.overview(req.query));
exports.people = handle((req) => analytics.people(req.query));
exports.person = handle((req) => analytics.person(String(req.params.id), req.user.uid));
exports.money = handle((req) => analytics.money(req.query));
exports.messaging = handle((req) => analytics.messaging(req.query));
