// controllers/scanActions/scanActionController.js
// Scan Actions: make a QR, read what a code does, do it (services/scanActionService).
const scanActions = require('../../services/scanActionService');
const { sendServiceError } = require('../../utils/serviceError');
const { SCAN_GUIDES } = require('../../config/scanGuides');

// @route   POST /api/scan-actions
//          body: { kind: 'place'|'placeSet'|'storeSetup', ... } (see the service)
// @access  Private
exports.createAction = async (req, res) => {
  try {
    const data = await scanActions.create(req.user, req.body || {});
    res.status(201).json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ scan action create failed', fallbackMessage: 'Couldn’t make the QR' });
  }
};

// @route   GET /api/scan-actions/:code
// @access  Public (signed in: also says which places the viewer already has)
exports.resolveAction = async (req, res) => {
  try {
    const viewerId = req.user ? req.user.uid : null;
    const data = await scanActions.resolve(req.params.code, viewerId);
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ scan action resolve failed', fallbackMessage: 'Couldn’t read the code' });
  }
};

// @route   POST /api/scan-actions/:code/complete
//          body: { globalPlaceIds?, circleId?, requestId? } | { contactName?, contactEmail?, contactPhone? }
// @access  Private
exports.completeAction = async (req, res) => {
  try {
    const data = await scanActions.complete(req.params.code, req.user, req.body || {});
    res.json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ scan action complete failed', fallbackMessage: 'Couldn’t finish that' });
  }
};

// @route   GET /api/scan-actions/guides
// @access  Public — the fixed "show me how" QR codes and their words
exports.listGuides = (req, res) => {
  res.set('Cache-Control', 'public, max-age=3600');
  res.json({
    success: true,
    data: {
      guides: SCAN_GUIDES.map(({ id, appGuide, title, blurb, storeOwner }) => ({
        id, appGuide, title, blurb, storeOwner: storeOwner === true, url: scanActions.urlFor(id)
      }))
    }
  });
};
