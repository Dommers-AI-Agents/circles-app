// middleware/appAttestMonitor.js
// Checks the App Attest assertion on requests that move points or coins and
// logs the outcome (2026-11-01). Monitor only: never refuses a request
// unless APP_ATTEST_ENFORCE=true, and even then only a build that declared
// it can attest and then sent a bad or missing assertion.
const appAttest = require('../services/appAttest/appAttestService');

module.exports = async function appAttestMonitor(req, res, next) {
  const path = String(req.originalUrl || '').split('?')[0];
  const outcome = await appAttest.checkRequest({ method: req.method, path, headers: req.headers, userId: req.user && req.user.uid });
  const capable = appAttest.declaresAttest(req.headers);
  console.info(`[app-attest] ${outcome.status} route=${req.method} ${path} uid=${req.user && req.user.uid} capable=${capable} reason=${outcome.reason}`);
  req.appAttest = outcome;
  if (appAttest.enforcing() && capable && outcome.status !== 'verified') {
    return res.status(403).json({ success: false, code: 'APP_ATTEST_REQUIRED', message: 'Update FavCircles and try again.' });
  }
  next();
};
