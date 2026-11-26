// backend/controllers/venues/venueClipWelcomeController.js
// The store's App Clip screens after Open (Welcome, sign-in, connected):
// the owner sees them as customers will and changes the words, rows, points,
// Wallet and the sign-in photo (Wes, 2026-11-26). Changes show at the next
// scan; Apple's card before Open is separate (appClipExperienceService).

const { getFirestore } = require('../../config/firebase');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const { cleanOverrides, ROW_KINDS } = require('../../services/clipExperience');
const { experienceForVenue } = require('../../services/clipExperienceStore');

const db = getFirestore();

const reply = (venue, { experience, gallery, loyaltyLive }) => ({
  overrides: venue.clipExperience || {},
  experience,
  photos: gallery.photoUrls,
  rowKinds: ROW_KINDS,
  rewardsLive: loyaltyLive
});

// @route   GET /api/rewards/venues/:venueId/clip-welcome
// @access  The store's team, or a super-user (requireVenueOwner)
exports.getClipWelcome = async (req, res) => {
  try {
    const built = await experienceForVenue(req.venue);
    res.json({ success: true, data: reply(req.venue, built) });
  } catch (error) {
    console.error('❌ Clip welcome read failed:', error);
    res.status(500).json({ success: false, error: 'Failed to load the App Clip screens' });
  }
};

// @route   PUT /api/rewards/venues/:venueId/clip-welcome
// @body    any of shortName, welcomeLine, doneLine, rows, showRewards,
//          showWallet, connectPhotoUrl, menuUrl (null = back to default)
exports.updateClipWelcome = async (req, res) => {
  try {
    const venue = req.venue;
    const { gallery } = await experienceForVenue(venue);
    const { overrides, errors } = cleanOverrides(req.body, {
      current: venue.clipExperience || {}, photoUrls: gallery.photoUrls
    });
    if (errors.length) return res.status(400).json({ success: false, error: errors.join('. ') });
    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId).update({
      clipExperience: overrides,
      updatedAt: new Date().toISOString()
    });
    const next = { ...venue, clipExperience: overrides };
    const built = await experienceForVenue(next, { gallery });
    res.json({ success: true, data: reply(next, built) });
  } catch (error) {
    console.error('❌ Clip welcome update failed:', error);
    res.status(500).json({ success: false, error: 'Failed to save the App Clip screens' });
  }
};
