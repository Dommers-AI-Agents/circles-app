// backend/controllers/adminDashboardController.js
//
// Read-only JSON for the admin dashboard (public/admin/index.html).
// Mounted behind protect + super-user in routes/adminDashboardRoutes.js.
const analytics = require('../services/adminAnalytics');
const { sendServiceError } = require('../utils/serviceError');
const { serializeDates } = require('../utils/wireDates');

const handle = (fn) => async (req, res) => {
  try {
    const body = await fn(req);
    if (body === null) return res.status(404).json({ success: false, message: 'Not found' });
    res.set('Cache-Control', 'no-store');
    return res.json({ success: true, ...serializeDates(body) });
  } catch (error) {
    return sendServiceError(res, error, { log: '📊 Admin dashboard error', fallbackMessage: 'Could not load the dashboard data' });
  }
};

exports.me = handle(async (req) => ({ admin: { id: req.user.uid, name: req.user.displayName || req.user.email || 'Admin' } }));
exports.overview = handle((req) => analytics.overview(req.query));
exports.people = handle((req) => analytics.people(req.query));
exports.person = handle((req) => analytics.person(String(req.params.id), req.user.uid));
exports.money = handle((req) => analytics.money(req.query));
exports.messaging = handle((req) => analytics.messaging(req.query));
// Email delivery: live login check of both routes + per-day outcomes
exports.emailHealth = handle(() => require('../services/emailHealth').dashboard({ days: 14 }));
// Instagram queue (services/instagramPublisher.js): see it, pause/approve a
// post, or post the next one now
const instagram = () => require('../services/instagramPublisher').createPublisher();
exports.instagram = handle(() => instagram().dashboard());
exports.instagramStatus = async (req, res) => {
  try {
    res.json({ success: true, ...(await instagram().setStatus(req.params.id, (req.body || {}).status)) });
  } catch (error) {
    res.status(error.status || 500).json({ success: false, message: error.status ? error.message : 'Could not update the post' });
  }
};
exports.instagramPostNow = async (req, res) => {
  try {
    const result = await instagram().publishNext({ force: true });
    res.status(result.posted ? 200 : 409).json({ success: !!result.posted, ...result, message: result.posted ? 'Posted' : (result.error || result.reason) });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
