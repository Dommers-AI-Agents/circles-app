// controllers/venues/venueAutomationsController.js
// Manage Store → Bring them back (2026-11-09): the store's automatic nudges
// (win-back, birthday, almost there) and how they've done. Business only;
// the rules live in services/storeAutomations.
const { getFirestore } = require('../../config/firebase');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const automations = require('../../services/storeAutomations');
const { sendServiceError } = require('../../utils/serviceError');

// @route   GET /api/rewards/venues/:venueId/automations
exports.get = async (req, res) => {
  try {
    res.json({ success: true, data: { settings: automations.settingsOf(req.venue), stats: await automations.stats(req.venue) } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to load store automations', fallbackMessage: 'Failed to load automations' });
  }
};

// @route   PUT /api/rewards/venues/:venueId/automations   body: the whole settings object
exports.update = async (req, res) => {
  try {
    const settings = automations.normalizeSettings(req.body);
    await getFirestore().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(req.venue.venueId)
      .update({ automations: settings, updatedAt: new Date().toISOString() });
    res.json({ success: true, data: { settings } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to save store automations', fallbackMessage: 'Failed to save automations' });
  }
};
