// middleware/notificationSeen.js
//
// After a request that opened something (a conversation, a place, a post…)
// succeeds, settle the viewer's bell rows about it. Runs after the response
// is sent, so it never slows or fails the request. The table lives in
// services/notificationSeen.js.
const { originFor, markSeen } = require('../services/notificationSeen');

module.exports = function notificationSeen(req, res, next) {
  const origin = originFor(req.method, req.path, req.query);
  if (origin) {
    res.on('finish', () => {
      const userId = req.user && req.user.uid;
      if (!userId || res.statusCode >= 400) return;
      markSeen(userId, origin)
        .then((n) => { if (n > 0) console.log(`🔔 ${n} notification(s) seen via ${origin.kind} ${origin.id}`); })
        .catch((e) => console.error(`🔔 notificationSeen ${origin.kind}: ${e.message}`));
    });
  }
  next();
};
