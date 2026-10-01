// backend/middleware/adminDashboardAuth.js
//
// Dashboard tokens are signed with their OWN key (derived from JWT_SECRET),
// so every other check in the app (protect, the refresh endpoint, legacy
// auth) rejects them: a token stolen from the dashboard page can read the
// dashboard for 12 hours and do nothing else. It can't post, edit places,
// manage stores, grant admin, or be traded for a normal app token.
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');

const AUDIENCE = 'favcircles-admin-dashboard';
const TTL = '12h';

const dashboardSecret = () => {
  if (!process.env.JWT_SECRET) throw new Error('JWT_SECRET is not set');
  return crypto.createHmac('sha256', process.env.JWT_SECRET).update('admin-dashboard-token-v1').digest('hex');
};

const signDashboardToken = (uid) => jwt.sign({ uid, scope: 'admin-dashboard' }, dashboardSecret(), { expiresIn: TTL, audience: AUDIENCE });

const bearer = (req) => {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7).trim() : null;
};

/** Accepts only a dashboard token for a current, unbanned super user. */
const requireDashboardToken = async (req, res, next) => {
  const token = bearer(req);
  let decoded;
  try {
    decoded = jwt.verify(token || '', dashboardSecret(), { audience: AUDIENCE });
  } catch (e) {
    return res.status(401).json({ success: false, code: 'SIGN_IN', message: 'Sign in to the dashboard again.' });
  }
  try {
    const snap = await getFirestore().collection('users').doc(decoded.uid).get();
    const user = snap.exists ? snap.data() : null;
    // Checked on every request, so removing someone's admin takes effect at once
    if (!user || user.isSuperUser !== true || user.banned === true || user.isDeleted) {
      return res.status(403).json({ success: false, code: 'NOT_ADMIN', message: "This account isn't an admin." });
    }
    req.user = { ...user, uid: decoded.uid, id: decoded.uid };
    return next();
  } catch (e) {
    return res.status(500).json({ success: false, message: 'Could not check your sign-in.' });
  }
};

module.exports = { signDashboardToken, requireDashboardToken, dashboardSecret, AUDIENCE };
