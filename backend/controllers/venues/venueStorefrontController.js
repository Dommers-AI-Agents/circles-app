// backend/controllers/venues/venueStorefrontController.js
// The owner's storefront: menu/services/products, the money buttons, and a
// gallery. Each block is replaced whole on PUT — the editor screens hold the
// full list, so partial merges would only invent ordering bugs.
const { getFirestore } = require('../../config/firebase');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const storefront = require('../../services/venueStorefront');
const db = getFirestore();

const save = async (venueId, key, value) => {
  const now = new Date().toISOString();
  await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId)
    .update({ [`storefront.${key}`]: value, 'storefront.updatedAt': now, updatedAt: now });
};

const reply = (res, venue, key, value) => {
  const merged = { ...venue, storefront: { ...(venue.storefront || {}), [key]: value } };
  res.json({ success: true, data: storefront.ownerStorefront(merged) });
};

// @route GET /api/rewards/venues/:venueId/storefront   (owner view)
exports.getStorefront = async (req, res) => {
  res.json({ success: true, data: storefront.ownerStorefront(req.venue) });
};

// @route PUT /api/rewards/venues/:venueId/storefront/offerings   (Business)
exports.updateOfferings = async (req, res) => {
  try {
    const { value, errors } = storefront.normalizeOfferings(req.body || {});
    if (errors.length) return res.status(400).json({ success: false, error: errors.join('. ') });
    await save(req.venue.venueId, 'offerings', value);
    reply(res, req.venue, 'offerings', value);
  } catch (error) {
    console.error('❌ Failed to update offerings:', error);
    res.status(500).json({ success: false, error: 'Failed to save' });
  }
};

// @route PUT /api/rewards/venues/:venueId/storefront/actions   (free)
exports.updateActions = async (req, res) => {
  try {
    const { value, errors } = storefront.normalizeActions(req.body || {});
    if (errors.length) return res.status(400).json({ success: false, error: errors.join('. ') });
    await save(req.venue.venueId, 'actions', value);
    reply(res, req.venue, 'actions', value);
  } catch (error) {
    console.error('❌ Failed to update actions:', error);
    res.status(500).json({ success: false, error: 'Failed to save' });
  }
};

// @route PUT /api/rewards/venues/:venueId/storefront/gallery   (Business)
//        body: { photos: [{ photoId?, url, caption? }] }
exports.updateGallery = async (req, res) => {
  try {
    const { value, errors } = storefront.normalizeGallery((req.body || {}).photos);
    if (errors.length) return res.status(400).json({ success: false, error: errors.join('. ') });
    await save(req.venue.venueId, 'gallery', value);
    reply(res, req.venue, 'gallery', value);
  } catch (error) {
    console.error('❌ Failed to update gallery:', error);
    res.status(500).json({ success: false, error: 'Failed to save' });
  }
};
