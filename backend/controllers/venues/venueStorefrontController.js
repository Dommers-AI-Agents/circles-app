// backend/controllers/venues/venueStorefrontController.js
// The owner's storefront: menu/services/products, the money buttons, and a
// gallery. Each block is replaced whole on PUT — the editor screens hold the
// full list, so partial merges would only invent ordering bugs.
const { getFirestore } = require('../../config/firebase');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const storefront = require('../../services/venueStorefront');
const { sendServiceError } = require('../../utils/serviceError');
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
  // A store gets its web address the first time its owner opens Manage
  // Store (best-effort: the rest of the screen never waits on it)
  if (!req.venue.slug && req.venue.isVirtual !== true) {
    await require('../../services/venueSlugService').ensureSlug(req.venue)
      .catch((e) => console.warn('Venue slug mint failed:', e.message));
  }
  res.json({ success: true, data: storefront.ownerStorefront(req.venue) });
};

// @route PUT /api/rewards/venues/:venueId/slug   body: { slug }   (primary owner)
// The store's web address, order.favcircles.com/<slug>. Old addresses keep
// working as redirects.
exports.setSlug = async (req, res) => {
  try {
    if (!req.isPrimaryVenueOwner) {
      return res.status(403).json({ success: false, code: 'owner_only', message: 'Only the store’s owner can change its web address.' });
    }
    const result = await require('../../services/venueSlugService').setSlug(req.venue, (req.body || {}).slug);
    res.json({ success: true, data: result });
  } catch (error) {
    require('../../utils/serviceError').sendServiceError(res, error, { log: 'Slug change failed', fallbackCode: 'slug_failed', fallbackMessage: 'Couldn’t change the web address. Try again.' });
  }
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

// @route PUT /api/rewards/venues/:venueId/storefront/menu   (Business)
//        body: { sections: [{ id?, name, items: [{ id?, name, price?, description?, tags? }] }], source? }
exports.updateMenu = async (req, res) => {
  try {
    const { value, errors } = storefront.normalizeMenu(req.body || {});
    if (errors.length) return res.status(400).json({ success: false, error: errors.join('. ') });
    await save(req.venue.venueId, 'menu', value);
    reply(res, req.venue, 'menu', value);
  } catch (error) {
    console.error('❌ Failed to update menu:', error);
    res.status(500).json({ success: false, error: 'Failed to save' });
  }
};

// @route POST /api/rewards/venues/:venueId/scan   (Business)
//        body: { kind: 'menu' | 'hours' | 'flyer', images: [base64] }
// A draft for the matching editor; nothing is saved (services/scan).
exports.scan = async (req, res) => {
  try {
    const result = await require('../../services/scan').scan({
      kind: (req.body || {}).kind, images: (req.body || {}).images, venue: req.venue, userId: req.user.uid
    });
    res.json({ success: true, data: result });
  } catch (error) {
    sendServiceError(res, error, { log: 'Venue scan failed', fallbackCode: 'scan_failed', fallbackMessage: 'Couldn\u2019t read that photo. Try again or fill it in by hand.' });
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
