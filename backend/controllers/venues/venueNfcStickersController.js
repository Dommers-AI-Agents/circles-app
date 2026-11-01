// controllers/venues/venueNfcStickersController.js
// Manage Store → NFC stickers: the store's tagged window links, written onto
// stickers by the owner's phone, with taps per sticker. Free for every store,
// like the window sticker itself.
const nfcStickers = require('../../services/nfcStickerService');
const rewardService = require('../../services/rewardService');
const { sendServiceError } = require('../../utils/serviceError');

// windowUrl: the untagged link, so "Check a sticker" can tell this store's
// stickers from anything else
const listData = (venue) => ({
  venueId: venue.venueId,
  stickers: nfcStickers.listStickers(venue),
  windowUrl: venue.windowCode ? rewardService.stickerUrl(venue.windowCode) : null
});

// @route   GET /api/rewards/venues/:venueId/nfc-stickers
exports.listStickers = async (req, res) => {
  res.json({ success: true, data: listData(req.venue) });
};

// @route   POST /api/rewards/venues/:venueId/nfc-stickers  { label }
exports.createSticker = async (req, res) => {
  try {
    const sticker = await nfcStickers.createSticker(req.venue, req.body?.label);
    res.status(201).json({ success: true, data: sticker });
  } catch (error) {
    sendServiceError(res, error, { log: 'NFC sticker create', fallbackCode: 'STICKER_FAILED', fallbackMessage: 'Could not add the sticker' });
  }
};

// @route   POST /api/rewards/venues/:venueId/nfc-stickers/:tag/written  { locked }
exports.markWritten = async (req, res) => {
  try {
    await nfcStickers.markWritten(req.venue, req.params.tag, { locked: req.body?.locked === true });
    res.json({ success: true });
  } catch (error) {
    sendServiceError(res, error, { log: 'NFC sticker written', fallbackCode: 'STICKER_FAILED', fallbackMessage: 'Could not update the sticker' });
  }
};

// @route   PATCH /api/rewards/venues/:venueId/nfc-stickers/:tag  { label }
exports.renameSticker = async (req, res) => {
  try {
    await nfcStickers.renameSticker(req.venue, req.params.tag, req.body?.label);
    res.json({ success: true });
  } catch (error) {
    sendServiceError(res, error, { log: 'NFC sticker rename', fallbackCode: 'STICKER_FAILED', fallbackMessage: 'Could not rename the sticker' });
  }
};

// @route   DELETE /api/rewards/venues/:venueId/nfc-stickers/:tag
exports.deleteSticker = async (req, res) => {
  try {
    await nfcStickers.deleteSticker(req.venue, req.params.tag);
    res.json({ success: true });
  } catch (error) {
    sendServiceError(res, error, { log: 'NFC sticker delete', fallbackCode: 'STICKER_FAILED', fallbackMessage: 'Could not remove the sticker' });
  }
};
