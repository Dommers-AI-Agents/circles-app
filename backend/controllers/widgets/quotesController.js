// backend/controllers/widgets/quotesController.js
// The daily quote widget's settings and its scheduler tick. Handlers pass
// named fields to the service; the service decides what is valid.
const quotes = require('../../services/quotesService');

const { sendServiceError } = require('../../utils/serviceError');
const fail = (res, error) => sendServiceError(res, error, {
  log: '[quotes] request failed', fallbackCode: 'quotes_failed', fallbackMessage: 'Something went wrong with quotes.'
});

exports.getSettings = async (req, res) => {
  try { res.json({ success: true, ...(await quotes.getSettings(req.user.uid)) }); } catch (e) { fail(res, e); }
};

exports.updateSettings = async (req, res) => {
  const { enabled, categories, time, times, email } = req.body || {};
  try { res.json({ success: true, ...(await quotes.updateSettings(req.user.uid, { enabled, categories, time, times, email })) }); }
  catch (e) { fail(res, e); }
};

// Cloud Scheduler, hourly. Each user is gated on their own local clock.
exports.runDue = async (req, res) => {
  try {
    const result = await quotes.runDue({
      userId: req.body && req.body.userId,
      force: req.body && req.body.force === true,
      dryRun: req.body && req.body.dryRun === true
    });
    console.log('💬 quotes run:', JSON.stringify(result));
    res.json({ success: true, ...result });
  } catch (e) { fail(res, e); }
};
