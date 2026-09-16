// backend/controllers/widgets/widgetDataController.js
// Generic widget document API for the home Widgets tab. The server stores
// opaque JSON per (user, widgetId) with an optimistic version lock; widget
// schemas live entirely in the iOS FavWidgets package.
const widgetDataService = require('../../services/widgetDataService');
const { ValidationError, VersionConflictError, SchemaTooOldError } = require('../../services/widgetDataService');
const piggyBankService = require('../../services/piggyBankService');

// Read at call time so the flag can flip without a restart in tests.
const piggyEnabled = () => process.env.WIDGET_PIGGY_ENABLED === '1';
const utcDay = (iso) => (iso ? String(iso).slice(0, 10) : null);

function sendError(res, error, fallback) {
  if (error instanceof ValidationError) {
    return res.status(error.status).json({ success: false, code: error.code, message: error.message });
  }
  console.error(`🧩 ${fallback}:`, error.message);
  return res.status(500).json({ success: false, message: fallback });
}

// @desc    Batch read widget documents (?ids=water,calories,calories_2026-09)
// @route   GET /api/widgets/data
// @access  Private
exports.listData = async (req, res) => {
  try {
    const raw = typeof req.query.ids === 'string' ? req.query.ids : '';
    const ids = raw.split(',').map(s => s.trim()).filter(Boolean);
    const documents = await widgetDataService.getMany(req.user.uid, ids);
    res.status(200).json({ success: true, documents });
  } catch (error) {
    sendError(res, error, 'Failed to load widget data');
  }
};

// @desc    Read one widget document (null if never saved — still 200)
// @route   GET /api/widgets/data/:widgetId
// @access  Private
exports.getData = async (req, res) => {
  try {
    const document = await widgetDataService.get(req.user.uid, req.params.widgetId);
    res.status(200).json({ success: true, document });
  } catch (error) {
    sendError(res, error, 'Failed to load widget document');
  }
};

// @desc    Save a widget document with optimistic versioning
// @route   PUT /api/widgets/data/:widgetId
// @access  Private
exports.putData = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { widgetId } = req.params;
    const { version, payload, schemaVersion } = req.body || {};
    const result = await widgetDataService.save(userId, widgetId, { version, payload, schemaVersion });

    // First save of the UTC day earns the daily-use coin; repeat saves cost
    // nothing extra because the previous updatedAt rides on the write result.
    // `prefs` is the tab's own bookkeeping, not a widget being used.
    let piggyBank;
    if (piggyEnabled() && widgetId !== 'prefs') {
      const today = utcDay(result.document.updatedAt);
      if (utcDay(result.previousUpdatedAt) !== today) {
        piggyBank = await piggyBankService.credit({
          userId,
          eventType: 'widget_daily_use',
          sourceRef: { docId: `${userId}_${widgetId}`, widgetId }
        });
      }
    }

    res.status(result.created ? 201 : 200).json({
      success: true,
      document: result.document,
      ...(piggyBank && piggyBank.credited ? { piggyBank } : {})
    });
  } catch (error) {
    if (error instanceof SchemaTooOldError) {
      // Deliberately NOT a merge-and-retry. This client cannot represent the
      // document it is holding, so retrying would overwrite fields it silently
      // dropped on decode. Refusing the write is what protects the data.
      return res.status(409).json({
        success: false,
        code: error.code,
        message: 'This widget was saved by a newer version of the app — update to make changes here',
        current: error.current
      });
    }
    if (error instanceof VersionConflictError) {
      return res.status(409).json({
        success: false,
        code: error.code,
        message: 'This widget was updated elsewhere — merge and try again',
        current: error.current
      });
    }
    sendError(res, error, 'Failed to save widget document');
  }
};

// @desc    Delete a widget document
// @route   DELETE /api/widgets/data/:widgetId
// @access  Private
exports.deleteData = async (req, res) => {
  try {
    await widgetDataService.remove(req.user.uid, req.params.widgetId);
    res.status(200).json({ success: true });
  } catch (error) {
    sendError(res, error, 'Failed to delete widget document');
  }
};
