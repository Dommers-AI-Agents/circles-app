// backend/services/storePagePreview.js
// What a store's web page (views/storePage.js) says before anyone signs in:
// the store, its photo, and what THIS code pays, in the same terms the App
// Clip's preview uses (controllers/clipController.getVenuePreview): points
// only where the store's rewards are live, the save bonus on a window code,
// the visit's points on a register code or a points sticker.
//
// The page is for phones with no app and no App Clip (Wes, 2026-11-26:
// "account for Android users ... a website to sign up for store
// notifications and rewards"). Counting the scan stays with the route, and
// nothing here bumps the clip's numbers.
const rewardService = require('./rewardService');
const rewardProgress = require('./rewardProgress');
const nfcStickers = require('./nfcStickerService');
const { activeOffers, venueGlobalPlaceId } = require('./venueHelpers');

/** Off puts every phone back on the "Get the App" page. */
const storeWebPageEnabled = () => process.env.STORE_WEB_PAGE !== 'false';

/**
 * Pure: the page's data from what was looked up.
 * `venue` is rewardService.findVenueByCode's result (it carries `kind`).
 */
const assemble = ({ venue, code, isRegister, loyaltyLive, coverUrl, globalPlaceId, coupon, tag }) => {
  const offers = loyaltyLive ? rewardProgress.rewardLadder(activeOffers(venue)) : [];
  const scanPoints = !loyaltyLive ? 0
    : isRegister ? rewardService.effectiveEarnRate(venue) : rewardService.effectiveSavePoints(venue);
  return {
    code,
    tag: tag || null,
    kind: isRegister ? 'register' : 'window',
    venueId: venue.venueId,
    globalPlaceId: globalPlaceId || null,
    name: venue.placeName || venue.venueName,
    address: venue.placeAddress || null,
    coverUrl: coverUrl || null,
    loyaltyLive,
    scanPoints,
    earnRate: loyaltyLive ? rewardService.effectiveEarnRate(venue) : null,
    offers,
    coupon: coupon && coupon.available !== false ? { couponId: coupon.couponId, title: coupon.title } : null
  };
};

/**
 * The page's data for a scanned code, or null when the code is unknown,
 * switched off, or the generic "Join FavCircles" code (never a store).
 */
async function previewForCode(code, { tag = null, couponId = null, venue: known = null } = {}) {
  const venue = known || await rewardService.findVenueByCode(code);
  if (!venue || venue.active === false || venue.genericJoin) return null;
  const { registerScanEarns, isVenueLoyaltyActive } = require('./ownerSubscriptionService');
  const isRegister = venue.kind === 'register' || !!nfcStickers.pointsStickerTag(venue, tag);
  const [loyaltyLive, gallery, globalPlaceId] = await Promise.all([
    isRegister ? registerScanEarns(venue).then((r) => r.earns) : isVenueLoyaltyActive(venue),
    require('./placePhotoService').venueGallery(venue).catch(() => ({ coverUrl: null })),
    venueGlobalPlaceId(venue).catch(() => null)
  ]);
  const coupon = couponId ? require('./storeCoupons').preview(venue, couponId) : null;
  return assemble({ venue, code, isRegister, loyaltyLive, coverUrl: gallery.coverUrl, globalPlaceId, coupon, tag });
}

module.exports = { storeWebPageEnabled, assemble, previewForCode };
