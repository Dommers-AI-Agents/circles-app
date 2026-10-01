// Alerts the admin when 5xx responses spike. Counts per Cloud Run instance in
// a sliding 5-minute window; when an instance sees `threshold` errors it
// raises one admin alert (de-duplicated to one an hour across instances by
// services/adminAlerts). Before this, a broken deploy or endpoint was only
// noticed when someone complained (security audit 2026-10-01).
const WINDOW_MS = 5 * 60 * 1000;

function errorRateMonitor({ threshold = Number(process.env.ERROR_ALERT_THRESHOLD) || 25, alert } = {}) {
  let events = []; // { at, path }
  const raise = alert || ((payload) => require('../services/adminAlerts').alertAdmin(payload));
  return (req, res, next) => {
    res.on('finish', () => {
      if (res.statusCode < 500) return;
      const now = Date.now();
      events = events.filter((e) => now - e.at < WINDOW_MS);
      events.push({ at: now, path: `${req.method} ${(req.baseUrl || '') + (req.route ? req.route.path : req.path)}` });
      if (events.length === threshold) {
        const top = Object.entries(events.reduce((m, e) => ({ ...m, [e.path]: (m[e.path] || 0) + 1 }), {}))
          .sort((a, b) => b[1] - a[1]).slice(0, 5).map(([p, n]) => `${n}× ${p}`).join('\n');
        raise({ key: 'errors_5xx', title: `${threshold}+ server errors in 5 minutes`, body: `Top endpoints:\n${top}\n\nRevision: ${process.env.K_REVISION || 'local'}` });
      }
    });
    next();
  };
}

module.exports = { errorRateMonitor };
