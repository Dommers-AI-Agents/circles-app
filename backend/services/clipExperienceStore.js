// backend/services/clipExperienceStore.js
// A store's App Clip screens with their live inputs (photos, rewards), for
// the clip preview and for the owner's editor. See services/clipExperience.js.

const placePhotos = require('./placePhotoService');
const rewardService = require('./rewardService');
const { buildClipExperience } = require('./clipExperience');

const EMPTY_GALLERY = { globalPlace: null, coverUrl: null, photoUrls: [] };

/**
 * @param {object} venue  the stickerVenues record (with any clipExperience)
 * @param {object} [opts] { gallery } when the caller already read it
 * @returns {Promise<{experience, gallery, loyaltyLive}>}
 */
async function experienceForVenue(venue, opts = {}) {
  const { isVenueLoyaltyActive } = require('./ownerSubscriptionService');
  const { activeOffers } = require('./venueHelpers');
  const rewardProgress = require('./rewardProgress');
  const gallery = opts.gallery || await placePhotos.venueGallery(venue).catch(() => EMPTY_GALLERY);
  const loyaltyLive = await isVenueLoyaltyActive(venue);
  const offers = loyaltyLive ? rewardProgress.rewardLadder(activeOffers(venue)) : [];
  const experience = buildClipExperience({
    venue,
    globalPlace: gallery.globalPlace,
    loyaltyLive,
    offers,
    earnRate: loyaltyLive ? rewardService.effectiveEarnRate(venue) : null,
    savePoints: loyaltyLive ? rewardService.effectiveSavePoints(venue) : 0,
    coverUrl: gallery.coverUrl,
    photoUrls: gallery.photoUrls
  });
  return { experience, gallery, loyaltyLive };
}

module.exports = { experienceForVenue };
