// backend/routes/adminDashboardRoutes.js — /api/admin/dashboard/*
// Super users only (users.isSuperUser, set with scripts/setSuperUser.js).
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const c = require('../controllers/adminDashboardController');

const handoff = require('../services/adminHandoff');
const { sendServiceError } = require('../utils/serviceError');

const router = express.Router();

// Public: the page trades a one-time code from the app for a 12-hour token.
// Registered before the admin guard below; the code itself proves who you are.
router.post('/handoff/redeem', express.json(), async (req, res) => {
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
router.post('/email-code/request', express.json(), codeRoute((b) => handoff.requestEmailCode(b.email)));
router.post('/email-code/verify', express.json(), codeRoute((b) => handoff.verifyEmailCode(b.email, b.code)));

router.use(protect, (req, res, next) => {
  if (req.user && req.user.isSuperUser === true) return next();
  return res.status(403).json({ success: false, code: 'NOT_ADMIN', message: "This account isn't an admin." });
});

router.get('/me', c.me);
// The app (signed in, admin) asks for a one-time code to open the page with
router.post('/handoff', async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, ...(await handoff.issue(req.user.uid)) });
  } catch (error) {
    sendServiceError(res, error, { log: 'Admin handoff issue failed', fallbackMessage: 'Could not open the dashboard.' });
  }
});
router.get('/overview', c.overview);
router.get('/people', c.people);
router.get('/people/:id', c.person);
router.get('/money', c.money);
router.get('/messaging', c.messaging);

module.exports = router;
