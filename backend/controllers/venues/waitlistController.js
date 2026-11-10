// controllers/venues/waitlistController.js
// The store's waitlist (2026-11-09; services/waitlistService): customers join
// and leave from the App Clip or place page and see their place in line;
// the host's screen lists the line and notifies, seats or removes. Business.
const waitlist = require('../../services/waitlistService');
const { sendServiceError } = require('../../utils/serviceError');

const fail = (res, error, what) => sendServiceError(res, error, { log: `❌ Waitlist ${what} failed`, fallbackMessage: `Couldn't ${what}` });

// ---- customer (routes/waitlistRoutes.js, /api/waitlist)

// @route POST /api/waitlist/:venueId/join   body: { partySize, name? }
exports.join = async (req, res) => {
  try {
    const entry = await waitlist.join({ venueId: req.params.venueId, userId: req.user.uid, partySize: (req.body || {}).partySize, name: (req.body || {}).name });
    res.status(entry.alreadyInLine ? 200 : 201).json({ success: true, data: entry });
  } catch (error) { fail(res, error, 'join the waitlist'); }
};

// @route GET /api/waitlist/:venueId/mine
exports.mine = async (req, res) => {
  try {
    res.json({ success: true, data: { entry: await waitlist.mine(req.params.venueId, req.user.uid) } });
  } catch (error) { fail(res, error, 'load your spot'); }
};

// @route POST /api/waitlist/entries/:entryId/leave
exports.leave = async (req, res) => {
  try {
    res.json({ success: true, data: await waitlist.leave(req.params.entryId, req.user.uid) });
  } catch (error) { fail(res, error, 'leave the waitlist'); }
};

// ---- host (routes/rewardRoutes.js, requireVenueOwner + requireOwnerPremium)

// @route GET /api/rewards/venues/:venueId/waitlist
exports.list = async (req, res) => {
  try {
    res.json({ success: true, data: { settings: waitlist.settingsOf(req.venue), line: await waitlist.line(req.venue) } });
  } catch (error) { fail(res, error, 'load the waitlist'); }
};

// @route PUT /api/rewards/venues/:venueId/waitlist   body: { enabled, quoteMinutes }
exports.saveSettings = async (req, res) => {
  try {
    res.json({ success: true, data: { settings: await waitlist.saveSettings(req.venue, req.body || {}) } });
  } catch (error) { fail(res, error, 'save the waitlist settings'); }
};

// @route POST /api/rewards/venues/:venueId/waitlist/:entryId/:action   notify | seat | remove
exports.act = async (req, res) => {
  try {
    res.json({ success: true, data: await waitlist.act(req.venue, req.params.entryId, req.params.action) });
  } catch (error) { fail(res, error, 'update the waitlist'); }
};
