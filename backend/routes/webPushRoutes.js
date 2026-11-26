// backend/routes/webPushRoutes.js — a browser turns the web app's
// notifications on or off (services/webPush.js). Mounted at /api/web-push.
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const { sendServiceError } = require('../utils/serviceError');
const webPush = require('../services/webPush');

const router = express.Router();

// The public half of the key the browser subscribes with (null = off)
router.get('/key', (req, res) => {
  res.json({ success: true, data: { publicKey: webPush.enabled() ? webPush.publicKey() : null } });
});

router.post('/subscribe', protect, async (req, res) => {
  try {
    res.json({ success: true, data: await webPush.subscribe(req.user.uid, (req.body || {}).subscription, { userAgent: req.get('user-agent') }) });
  } catch (error) {
    sendServiceError(res, error, { log: '🌐 Web push subscribe failed', fallbackMessage: "Couldn't turn notifications on. Please try again." });
  }
});

router.post('/unsubscribe', protect, async (req, res) => {
  try {
    res.json({ success: true, data: await webPush.unsubscribe(req.user.uid, (req.body || {}).endpoint) });
  } catch (error) {
    sendServiceError(res, error, { log: '🌐 Web push unsubscribe failed', fallbackMessage: "Couldn't turn notifications off. Please try again." });
  }
});

module.exports = router;
