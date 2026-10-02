// backend/routes/adminDashboardRoutes.js — /api/admin/dashboard/*
// Super users only (users.isSuperUser, set with scripts/setSuperUser.js).
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const { requireDashboardToken } = require('../middleware/adminDashboardAuth');
const { authLimiter } = require('../middleware/security');
const c = require('../controllers/adminDashboardController');

const handoff = require('../services/adminHandoff');
const { sendServiceError } = require('../utils/serviceError');

const router = express.Router();

// Public: the page trades a one-time code from the app for a 12-hour token.
// Registered before the admin guard below; the code itself proves who you are.
router.post('/handoff/redeem', authLimiter, express.json(), async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, ...(await handoff.redeem(req.body && req.body.code)) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Admin handoff redeem failed', fallbackMessage: 'Could not sign you in. Open the dashboard from the app again.' });
  }
});

// Public: sign in with a code emailed to an admin address (no password)
const codeRoute = (fn) => async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, ...(await fn(req.body || {})) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Admin email code failed', fallbackMessage: 'Something went wrong. Try again in a moment.' });
  }
};
router.post('/email-code/request', authLimiter, express.json(), codeRoute((b) => handoff.requestEmailCode(b.email)));
router.post('/email-code/verify', authLimiter, express.json(), codeRoute((b) => handoff.verifyEmailCode(b.email, b.code)));

// Issued to the APP's normal sign-in (the Settings row, or the page right
// after a password sign-in), and only to a super user.
router.post('/handoff', protect, async (req, res) => {
  if (!req.user || req.user.isSuperUser !== true) {
    return res.status(403).json({ success: false, code: 'NOT_ADMIN', message: "This account isn't an admin." });
  }
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, ...(await handoff.issue(req.user.uid)) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Admin handoff issue failed', fallbackMessage: 'Could not open the dashboard.' });
  }
});

// Everything else: dashboard tokens only (their own signing key, so they
// work nowhere else in the app, and an app token doesn't work here).
router.use(requireDashboardToken);

router.get('/me', c.me);
router.get('/overview', c.overview);
router.get('/people', c.people);
router.get('/people/:id', c.person);
router.get('/money', c.money);
router.get('/messaging', c.messaging);
router.get('/email-health', c.emailHealth);

module.exports = router;
