// backend/models/StickerModels.js
// Models for the sticker rewards program: venues with physical QR stickers
// and the reward-points event ledger.

const rewardConfig = require('../config/rewardConfig');

const STICKER_COLLECTIONS = {
  STICKER_VENUES: 'stickerVenues',
  REWARD_EVENTS: 'rewardEvents'
};

const REWARD_EVENT_TYPES = [
  'sticker_signup',
  'sticker_save',
  'venue_visit',
  'share_conversion',
  'redemption'
];

// Venue with a window sticker (discovery) and a register card (purchase proof).
// Offers are venue-honored discounts users redeem with points.
const createStickerVenue = (data, windowCode, registerCode) => {
  const now = new Date().toISOString();
  const emptyStats = { scans: 0, signups: 0, saves: 0, visits: 0, redemptions: 0 };

  return {
    venueName: data.venueName,
    contactName: data.contactName || null,
    contactEmail: data.contactEmail || null,
    // Owner account: the user who manages this venue's offers and earn rate.
    // Resolved from contactEmail at creation when possible; venues enrolled
    // before the owner signed up are lazily claimed by email in getMyVenues.
    ownerUserId: data.ownerUserId || null,
    ownerEmail: (data.contactEmail || '').trim().toLowerCase() || null,
    googlePlaceId: data.googlePlaceId || null,
    globalPlaceId: data.globalPlaceId || null,
    placeName: data.placeName || data.venueName,
    placeAddress: data.placeAddress || null,
    category: data.category || 'restaurant',
    // { lat, lng } — used to sort the browsable offers list by distance
    location: data.location || null,
    windowCode,
    registerCode,
    // Points awarded per register-card (purchase) scan; owner-adjustable
    earnRate: Number.isInteger(data.earnRate) && data.earnRate > 0
      ? data.earnRate
      : rewardConfig.POINTS.VENUE_VISIT,
    offers: (data.offers || []).map((offer, index) => ({
      offerId: offer.offerId || `offer_${index + 1}`,
      title: offer.title,
      pointsCost: offer.pointsCost,
      active: offer.active !== false
    })),
    stats: { ...emptyStats },
    // { "2026-07": { scans: 3, ... } } — fed into the monthly venue report email
    statsMonthly: {},
    active: true,
    createdAt: now,
    updatedAt: now,
    lastReportSentAt: null
  };
};

// Shared offer field rules, also used by the owner add/update-offer endpoints
const validateOfferInput = (offer, label = 'offer') => {
  const errors = [];
  if (offer.title !== undefined && (!offer.title || !String(offer.title).trim())) {
    errors.push(`${label}.title must not be empty`);
  }
  if (offer.pointsCost !== undefined
      && (!Number.isInteger(offer.pointsCost) || offer.pointsCost <= 0)) {
    errors.push(`${label}.pointsCost must be a positive integer`);
  }
  return errors;
};

const validateEarnRate = (earnRate) => {
  if (!Number.isInteger(earnRate) || earnRate <= 0 || earnRate > rewardConfig.EARN_RATE_MAX) {
    return [`earnRate must be a positive integer up to ${rewardConfig.EARN_RATE_MAX}`];
  }
  return [];
};

const validateStickerVenue = (data) => {
  const errors = [];
  if (!data.venueName || !data.venueName.trim()) {
    errors.push('venueName is required');
  }
  if (!data.googlePlaceId && !data.globalPlaceId) {
    errors.push('googlePlaceId or globalPlaceId is required so saves can be attributed');
  }
  if (data.location && (typeof data.location.lat !== 'number' || typeof data.location.lng !== 'number')) {
    errors.push('location must be { lat, lng } numbers');
  }
  if (data.earnRate !== undefined) {
    errors.push(...validateEarnRate(data.earnRate));
  }
  if (data.offers) {
    data.offers.forEach((offer, index) => {
      const label = `offers[${index}]`;
      if (offer.title === undefined) errors.push(`${label}.title is required`);
      if (offer.pointsCost === undefined) errors.push(`${label}.pointsCost is required`);
      errors.push(...validateOfferInput(offer, label));
    });
  }
  return errors;
};

// Ledger entry. The Firestore doc ID is the idempotency key, so a duplicate
// award fails at write time instead of needing a read-check race.
const createRewardEvent = (data) => {
  return {
    userId: data.userId,
    type: data.type,
    points: data.points,
    venueId: data.venueId || null,
    venueName: data.venueName || null,
    code: data.code || null,
    googlePlaceId: data.googlePlaceId || null,
    sourceUserId: data.sourceUserId || null,
    // Redemption voucher fields (only set for type === 'redemption')
    voucherCode: data.voucherCode || null,
    offerId: data.offerId || null,
    offerTitle: data.offerTitle || null,
    expiresAt: data.expiresAt || null,
    status: data.status || 'completed',
    createdAt: new Date().toISOString()
  };
};

// Doc IDs cannot contain '/', and '.' segments are reserved
const sanitizeKeyPart = (part) => String(part).replace(/[/.]/g, '_');

module.exports = {
  STICKER_COLLECTIONS,
  REWARD_EVENT_TYPES,
  createStickerVenue,
  validateStickerVenue,
  validateOfferInput,
  validateEarnRate,
  createRewardEvent,
  sanitizeKeyPart
};
