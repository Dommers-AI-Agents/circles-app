// Super-user gate for admin endpoints. Runs after `protect` (req.user set).
// Several admin-style routes used to need only a login (security audit
// 2026-10-01); every one of them goes through this now.
module.exports = function requireSuperUser(req, res, next) {
  if (req.user && req.user.isSuperUser === true) return next();
  return res.status(403).json({ success: false, error: 'Super-user access required' });
};
