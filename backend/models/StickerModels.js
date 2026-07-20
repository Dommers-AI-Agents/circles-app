// backend/models/StickerModels.js
// Models for the sticker rewards program: venues with physical QR stickers
// and the reward-points event ledger.

const rewardConfig = require('../config/rewardConfig');

const STICKER_COLLECTIONS = {
  STICKER_VENUES: 'stickerVenues',
  REWARD_EVENTS: 'rewardEvents',
  VENUE_CLAIM_REQUESTS: 'venueClaimRequests'
};

const CLAIM_STATUSES = ['pending', 'approved', 'denied'];

// Owner announcements shown on the venue's place page (deals, happy hours,
// events). Embedded on the venue doc like offers[]; expired ones are hidden
// from public reads and pruned from the doc well after expiry.
const MAX_ANNOUNCEMENTS = 20;

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
    announcements: [],
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

// Shared announcement field rules for the owner add/update endpoints.
// `expiresAt` may be null (no expiry) or a future ISO date string.
const validateAnnouncementInput = (announcement, label = 'announcement') => {
  const errors = [];
  if (announcement.title !== undefined) {
    const title = String(announcement.title || '').trim();
    if (!title) errors.push(`${label}.title must not be empty`);
    if (title.length > 80) errors.push(`${label}.title must be 80 characters or fewer`);
  }
  if (announcement.message !== undefined) {
    const message = String(announcement.message || '').trim();
    if (!message) errors.push(`${label}.message must not be empty`);
    if (message.length > 500) errors.push(`${label}.message must be 500 characters or fewer`);
  }
  if (announcement.expiresAt !== undefined && announcement.expiresAt !== null) {
    const expiry = new Date(announcement.expiresAt);
    if (Number.isNaN(expiry.getTime())) {
      errors.push(`${label}.expiresAt must be an ISO date string or null`);
    } else if (expiry <= new Date()) {
      errors.push(`${label}.expiresAt must be in the future`);
    }
  }
  return errors;
};

// Ownership claim filed from a place page. Doc ID is `${venueId}_${userId}`
// (or `place_${placeKey}_${userId}` when no rewards venue is enrolled yet),
// so a user can only ever hold one claim per business.
// The claimer supplies contact info; the admin is emailed for verification.
const createVenueClaimRequest = ({
  venueId, venueName, userId, userEmail, userDisplayName, message,
  contactName, contactEmail, contactPhone,
  placeId, globalPlaceId, googlePlaceId, placeName, placeAddress
}) => {
  const now = new Date().toISOString();
  return {
    venueId: venueId || null,
    venueName: venueName || placeName || null,
    userId,
    userEmail: (userEmail || '').trim().toLowerCase() || null,
    userDisplayName: userDisplayName || null,
    message: (message || '').trim() || null,
    // Contact info entered by the claimer — how the admin verifies ownership
    contactName: (contactName || '').trim() || null,
    contactEmail: (contactEmail || '').trim().toLowerCase() || null,
    contactPhone: (contactPhone || '').trim() || null,
    // Place references, for claims on businesses not yet in the sticker program
    placeId: placeId || null,
    globalPlaceId: globalPlaceId || null,
    googlePlaceId: googlePlaceId || null,
    placeName: placeName || null,
    placeAddress: placeAddress || null,
    status: 'pending',
    resolvedBy: null,
    resolvedAt: null,
    denialReason: null,
    createdAt: now,
    updatedAt: now
  };
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
  CLAIM_STATUSES,
  MAX_ANNOUNCEMENTS,
  createStickerVenue,
  validateStickerVenue,
  validateOfferInput,
  validateAnnouncementInput,
  validateEarnRate,
  createRewardEvent,
  createVenueClaimRequest,
  sanitizeKeyPart
};
