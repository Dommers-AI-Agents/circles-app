// services/venueHelpers.js
// Venue/reward helpers shared by the controllers split out of rewardController.js.

const { resolveGlobalPlace } = require('../services/globalPlaceResolver');
const { isSameUser } = require('../services/idService');

// ---------- Venue team ----------
// A venue's team = the billing owner (ownerUserId — exactly one account, the
// one whose Business subscription keeps the venue live) plus any managers the
// owner invited (managerUserIds). Managers get every day-to-day owner
// surface; billing, claims, and the storefront identity stay owner-only.
const venueManagerIds = (venue) =>
  (Array.isArray(venue?.managerUserIds) ? venue.managerUserIds : []).filter(Boolean);

const isVenueTeamMember = (venue, uid) => {
  if (!venue || !uid) return false;
  if (venue.ownerUserId && isSameUser(venue.ownerUserId, uid)) return true;
  return venueManagerIds(venue).some((id) => isSameUser(id, uid));
};

const publicVenueInfo = (venue) => ({
  venueId: venue.venueId,
  venueName: venue.venueName,
  placeName: venue.placeName,
  placeAddress: venue.placeAddress,
  category: venue.category || 'restaurant',
  googlePlaceId: venue.googlePlaceId,
  globalPlaceId: venue.globalPlaceId,
  location: venue.location || null,
  // Online-only brand venue: never on a map; Specials/profile/follow only
  isVirtual: venue.isVirtual === true
});

const activeOffers = (venue) => (venue.offers || []).filter((o) => o.active !== false);

// Resolve a venue's canonical globalPlaces doc id (venues enrolled before
// place normalization only carry a googlePlaceId).
const venueGlobalPlaceId = async (venue) => {
  if (venue.globalPlaceId) return venue.globalPlaceId;
  if (!venue.googlePlaceId) return null;
  try {
    const { globalPlaceDoc } = await resolveGlobalPlace(venue.googlePlaceId);
    return globalPlaceDoc ? globalPlaceDoc.id : null;
  } catch (error) {
    console.error('⚠️ Venue global-place resolution failed:', error.message);
    return null;
  }
};

module.exports = {
  venueManagerIds,
  isVenueTeamMember,
  publicVenueInfo,
  activeOffers,
  venueGlobalPlaceId
};
