// backend/controllers/widgets/medScanController.js — Medications widget:
// label photos → draft reminders the person checks before saving.
const { sendServiceError } = require('../../utils/serviceError');
const medScan = require('../../services/scan/medScan');

// @route POST /api/widgets/meds/scan   body: { images: [base64] } (up to 4)
exports.scan = async (req, res) => {
  try {
    const result = await medScan.scan({ images: (req.body || {}).images, userId: req.user.uid });
    res.json({ success: true, ...result });
  } catch (error) {
    sendServiceError(res, error, { log: 'Medication label scan failed', fallbackCode: 'scan_failed', fallbackMessage: 'Couldn’t read that label. Try again or add it by hand.' });
  }
};
