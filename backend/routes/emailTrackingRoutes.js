// backend/routes/emailTrackingRoutes.js
//
// /e/c — a click in one of our emails: verify, record, forward (302).
// /e/o — the open pixel: verify, record, 1×1 gif. No login: an email client
// carries no token, the HMAC in the link is the proof. Recording never
// delays or blocks the person: the redirect goes out first.
const express = require('express');
const tracking = require('../services/emailTracking');
const engagement = require('../services/emailEngagement');

const router = express.Router();
const GIF = Buffer.from('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7', 'base64');

const recordQuietly = (event, params, req) =>
  engagement.record(event, params, { userAgent: req.get('user-agent') })
    .catch((e) => console.warn(`📧 email ${event} not recorded: ${e.message}`));

router.get('/c', (req, res) => {
  const params = tracking.readParams(req.query || {});
  if (!params || !params.url) return res.status(400).type('text/plain').send('That link is incomplete.');
  res.redirect(302, params.url);
  recordQuietly('click', params, req);
});

router.get('/o', (req, res) => {
  const params = tracking.readParams(req.query || {});
  res.set({ 'Content-Type': 'image/gif', 'Cache-Control': 'no-store, private', 'Content-Length': GIF.length });
  res.end(GIF);
  if (params) recordQuietly('open', params, req);
});

module.exports = router;
