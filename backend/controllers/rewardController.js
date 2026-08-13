// backend/controllers/rewardController.js
// Sticker rewards endpoints: scan, save confirmation, balance, offer redemption,
// and admin venue management.

const { getFirestore } = require('../config/firebase');
const geofire = require('geofire-common');
const { COLLECTIONS } = require('../models/FirestoreModels');
const {
  validateStickerVenue,
  validateOfferInput,
  validateAnnouncementInput,
  validateEarnRate,
  createVenueClaimRequest,
  createRedemptionCode,
  validateRedemptionCodeBatch,
  sanitizeKeyPart,
  STICKER_COLLECTIONS,
  MAX_ANNOUNCEMENTS
} = require('../models/StickerModels');
const rewardService = require('../services/rewardService');
const rewardConfig = require('../config/rewardConfig');
const emailService = require('../services/emailService');
const { resolveGlobalPlace } = require('../services/globalPlaceResolver');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { isOwnerPremiumUser, isOwnerPremiumForVenue, isVenueLoyaltyActive, isCompActive, venueLoyaltyStatus } = require('../services/ownerSubscriptionService');
const { createActivity } = require('./activityController');
const sseService = require('../services/sseService');
const { normalizeUserId, isSameUser } = require('../services/idService');

const db = getFirestore();

// Did this user already save the venue's place? Checks the legacy `places`
// collection (what the iOS app writes today) by googlePlaceId + addedBy.
const userHasSavedVenuePlace = async (userId, venue) => {
  if (!venue.googlePlaceId) return false;
  try {
    const snapshot = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', userId)
      .where('googlePlaceId', '==', venue.googlePlaceId)
      .where('deletedAt', '==', null)
      .limit(1)
      .get();
    return !snapshot.empty;
  } catch (error) {
    console.error('⚠️ Saved-place lookup failed:', error.message);
    return false;
  }
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

// Batch-read the venues' canonical globalPlaces docs and map venueId → first
// photo URL (photos are stored as {url} objects or bare strings). Venues
// missing a stamped globalPlaceId fall back to a googlePlaceId lookup.
const firstPhotoUrl = (globalPlaceData) => {
  // Owner-curated cover wins over positional first photo
  if (globalPlaceData.coverPhotoUrl) return globalPlaceData.coverPhotoUrl;
  const first = (globalPlaceData.photos || [])[0];
  return typeof first === 'string' ? first : (first && first.url) || null;
};

const fetchVenuePhotoUrls = async (venues) => {
  const photoUrls = new Map();
  try {
    const byGlobalId = venues.filter((v) => v.globalPlaceId);
    if (byGlobalId.length > 0) {
      const ids = [...new Set(byGlobalId.map((v) => v.globalPlaceId))];
      const docs = await db.getAll(...ids.map((id) => db.collection('globalPlaces').doc(id)));
      const urlsById = new Map();
      docs.forEach((doc) => {
        if (doc.exists) urlsById.set(doc.id, firstPhotoUrl(doc.data()));
      });
      byGlobalId.forEach((v) => {
        const url = urlsById.get(v.globalPlaceId);
        if (url) photoUrls.set(v.venueId, url);
      });
    }

    const byGoogleId = venues.filter((v) => !v.globalPlaceId && v.googlePlaceId);
    await Promise.all(byGoogleId.map(async (v) => {
      const snapshot = await db.collection('globalPlaces')
        .where('googlePlaceId', '==', v.googlePlaceId)
        .limit(1)
        .get();
      if (snapshot.empty) return;
      const url = firstPhotoUrl(snapshot.docs[0].data());
      if (url) photoUrls.set(v.venueId, url);
    }));
  } catch (error) {
    console.error('⚠️ Venue photo lookup failed (continuing without photos):', error.message);
  }
  return photoUrls;
};

// @desc    Redeem a scanned sticker code (window or register)
// @route   POST /api/rewards/scan
// @access  Private
exports.scan = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { code } = req.body;

    if (!code) {
      return res.status(400).json({ success: false, error: 'code is required' });
    }

    const venue = await rewardService.findVenueByCode(code);
    if (!venue || venue.active === false) {
      return res.status(404).json({ success: false, error: 'Unknown sticker code' });
    }

    if (venue.kind === 'window') {
      rewardService.incrementVenueStats(venue.venueId, 'scans');
      const signupResult = await rewardService.awardStickerSignup(userId, venue);
      const alreadySaved = await userHasSavedVenuePlace(userId, venue);
      const { rewardPoints, venueBalances } = await rewardService.getBalance(userId);

      return res.json({
        success: true,
        data: {
          kind: 'window',
          venue: publicVenueInfo(venue),
          awarded: signupResult.awarded
            ? { type: 'sticker_signup', points: signupResult.points }
            : null,
          alreadySaved,
          balance: rewardPoints,
          venueBalance: (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0
        }
      });
    }

    // Register card: purchase proof (possession of the physical card is the
    // gate — points come from the venue's owner-configured earn rate).
    // Loyalty pauses gracefully when the owner's business subscription lapses —
    // never a scary error at the register.
    const loyalty = await venueLoyaltyStatus(venue);
    if (!loyalty.active) {
      console.warn(`[loyalty-integrity] register scan paused venue=${venue.venueId} reason=${loyalty.reason}`);
      const { rewardPoints, venueBalances } = await rewardService.getBalance(userId);
      return res.json({
        success: true,
        data: {
          kind: 'register',
          venue: publicVenueInfo(venue),
          awarded: null,
          loyaltyPaused: true,
          balance: rewardPoints,
          venueBalance: (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0,
          offers: []
        }
      });
    }
    // Comped venue awarding points has no paying subscriber — surface it so
    // revenue leakage is measurable, not invisible.
    if (loyalty.reason === 'comp') {
      console.info(`[loyalty-integrity] comped award venue=${venue.venueId} until=${venue.loyaltyCompedUntil || 'open-ended'} reason=${venue.loyaltyCompReason || 'unspecified'}`);
    }

    const visitResult = await rewardService.awardVenueVisit(userId, venue);

    const { rewardPoints, venueBalances } = await rewardService.getBalance(userId);
    return res.json({
      success: true,
      data: {
        kind: 'register',
        venue: publicVenueInfo(venue),
        awarded: visitResult.awarded
          ? { type: 'venue_visit', points: visitResult.points }
          : null,
        alreadyEarnedToday: visitResult.reason === 'already_today',
        balance: rewardPoints,
        venueBalance: (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0,
        offers: activeOffers(venue)
      }
    });
  } catch (error) {
    console.error('❌ Reward scan failed:', error);
    res.status(500).json({ success: false, error: 'Failed to process scan' });
  }
};

// @desc    Confirm the user saved the sticker venue's place, award save points
// @route   POST /api/rewards/sticker-save
// @access  Private
exports.confirmStickerSave = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { code } = req.body;

    if (!code) {
      return res.status(400).json({ success: false, error: 'code is required' });
    }

    const venue = await rewardService.findVenueByCode(code);
    if (!venue || venue.active === false) {
      return res.status(404).json({ success: false, error: 'Unknown sticker code' });
    }

    const saved = await userHasSavedVenuePlace(userId, venue);
    if (!saved) {
      return res.status(400).json({
        success: false,
        error: 'Save the place to one of your circles first'
      });
    }

    const result = await rewardService.awardStickerSave(userId, venue);
    const { rewardPoints, venueBalances } = await rewardService.getBalance(userId);

    res.json({
      success: true,
      data: {
        awarded: result.awarded ? { type: 'sticker_save', points: result.points } : null,
        alreadyAwarded: !!result.duplicate,
        balance: rewardPoints,
        venueBalance: (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0
      }
    });
  } catch (error) {
    console.error('❌ Sticker save confirmation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to confirm save' });
  }
};

// @desc    Points balance + recent reward history
// @route   GET /api/rewards/balance
// @access  Private
exports.getBalance = async (req, res) => {
  try {
    const { rewardPoints, venueBalances, events } = await rewardService.getBalance(req.user.uid);
    res.json({ success: true, data: { balance: rewardPoints, venueBalances, events } });
  } catch (error) {
    console.error('❌ Failed to load reward balance:', error);
    res.status(500).json({ success: false, error: 'Failed to load balance' });
  }
};

// @desc    Redeem points for a venue offer; returns a 5-minute voucher
// @route   POST /api/rewards/redeem-offer
// @access  Private
exports.redeemOffer = async (req, res) => {
  try {
    const { venueId, offerId } = req.body;
    if (!venueId || !offerId) {
      return res.status(400).json({ success: false, error: 'venueId and offerId are required' });
    }

    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId).get();
    if (venueDoc.exists && !(await isVenueLoyaltyActive({ venueId, ...venueDoc.data() }))) {
      return res.status(400).json({ success: false, error: 'Loyalty is paused at this venue' });
    }

    const result = await rewardService.redeemOffer(req.user.uid, venueId, offerId);
    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    const { rewardPoints, venueBalances } = await rewardService.getBalance(req.user.uid);
    res.json({
      success: true,
      data: {
        voucher: result.voucher,
        balance: rewardPoints,
        venueBalances,
        venueBalance: (venueBalances.find((v) => v.venueId === venueId) || {}).points || 0
      }
    });
  } catch (error) {
    console.error('❌ Offer redemption failed:', error);
    res.status(500).json({ success: false, error: 'Failed to redeem offer' });
  }
};

// @desc    Browse participating venues and their active offers.
//          Optional lat/lng query params add distance sorting; venues whose
//          place the user has saved are flagged and sorted first.
// @route   GET /api/rewards/offers
// @access  Private
exports.getOffers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const lat = parseFloat(req.query.lat);
    const lng = parseFloat(req.query.lng);
    const hasCoords = Number.isFinite(lat) && Number.isFinite(lng);

    // Single equality filter — served by the automatic index (no orderBy here;
    // adding one would require a composite index)
    const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .where('active', '==', true)
      .limit(200)
      .get();

    // Owners whose business subscription lapsed have their offers hidden
    // (announcements stay up until natural expiry). Unowned venues stay live.
    const allVenues = snapshot.docs.map((doc) => ({ venueId: doc.id, ...doc.data() }));
    const ownerIds = [...new Set(allVenues.map((v) => v.ownerUserId).filter(Boolean))];
    const ownerUsers = new Map();
    if (ownerIds.length > 0) {
      const ownerDocs = await db.getAll(
        ...ownerIds.map((id) => db.collection(COLLECTIONS.USERS).doc(id))
      );
      ownerDocs.forEach((doc) => { if (doc.exists) ownerUsers.set(doc.id, doc.data()); });
    }
    // Loyalty is live via an explicit comp OR a premium owner — no longer the
    // implicit "unowned => always live" pass (that ran the paid program free
    // and invisibly). Comp keeps hands-on pilot venues working. The owner's
    // subscription only covers the venue it was purchased for.
    const loyaltyLive = (venue) =>
      isCompActive(venue) || isOwnerPremiumForVenue(ownerUsers.get(venue.ownerUserId), venue.venueId, venue);

    // A venue belongs in the browse list only while its loyalty is live and it
    // has something to show — a redeemable offer or an announcement. A lapsed
    // owner's offers AND announcements are both hidden (consistent behavior).
    const liveVenues = allVenues
      .filter((venue) =>
        loyaltyLive(venue) &&
        (activeOffers(venue).length > 0 || rewardService.activeAnnouncements(venue).length > 0)
      );

    const savedPlaceIds = await rewardService.getSavedVenuePlaceIds(
      userId,
      liveVenues.map((venue) => venue.googlePlaceId)
    );

    const photoUrls = await fetchVenuePhotoUrls(liveVenues);

    const venues = liveVenues.map((venue) => ({
      ...publicVenueInfo(venue),
      earnRate: rewardService.effectiveEarnRate(venue),
      savedByUser: !!(venue.googlePlaceId && savedPlaceIds.has(venue.googlePlaceId)),
      photoUrl: photoUrls.get(venue.venueId) || null,
      distanceMeters: hasCoords && venue.location
        ? geofire.distanceBetween([lat, lng], [venue.location.lat, venue.location.lng]) * 1000
        : null,
      offers: (loyaltyLive(venue) ? activeOffers(venue) : []).map(({ offerId, title, pointsCost }) => ({
        offerId, title, pointsCost
      })),
      announcements: rewardService.activeAnnouncements(venue)
    }));

    // Saved venues first (alphabetical), then by distance, unknown-distance last
    venues.sort((a, b) => {
      if (a.savedByUser !== b.savedByUser) return a.savedByUser ? -1 : 1;
      if (!a.savedByUser) {
        if (a.distanceMeters !== null && b.distanceMeters !== null) {
          return a.distanceMeters - b.distanceMeters;
        }
        if (a.distanceMeters !== null) return -1;
        if (b.distanceMeters !== null) return 1;
      }
      return (a.venueName || '').localeCompare(b.venueName || '');
    });

    // Balance rides along so the home-screen badge and the rewards screen can
    // render from this one request (skip getBalance — no need for the history).
    // venueBalances lets the offers UI gate affordability per shop.
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const balance = userData.rewardPoints || 0;
    const venueBalances = rewardService.venueBalancesFrom(userData);

    res.json({
      success: true,
      data: { venues: venues.slice(0, rewardConfig.NEARBY_MAX_VENUES), balance, venueBalances }
    });
  } catch (error) {
    console.error('❌ Failed to load offers:', error);
    res.status(500).json({ success: false, error: 'Failed to load offers' });
  }
};

// @desc    Rewards data for a place page: the venue's offers, announcements,
//          the caller's balance/ownership, and claim eligibility. A place with
//          no enrolled venue returns { venue: null } — that's the common case.
// @route   GET /api/rewards/venues/by-place/:placeId?googlePlaceId=
// @access  Private
exports.getVenueByPlace = async (req, res) => {
  try {
    const userId = req.user.uid;
    const venue = await rewardService.findVenueByPlace(
      req.params.placeId,
      req.query.googlePlaceId
    );

    if (!venue) {
      // Not in the sticker program — but any resolvable place can be claimed
      // by its owner ("Is this your store?"). Claims are verified by a human,
      // so no Google backing is required: Apple-sourced saves (no
      // googlePlaceId) used to silently hide the claim card.
      let googlePlaceId = req.query.googlePlaceId || null;
      let globalPlaceId = null;
      let placeResolved = false;
      try {
        const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(req.params.placeId).get();
        if (placeDoc.exists) {
          placeResolved = true;
          googlePlaceId = placeDoc.data().googlePlaceId || googlePlaceId;
          globalPlaceId = placeDoc.data().globalPlaceId || null;
        } else {
          const globalDoc = await db.collection('globalPlaces').doc(req.params.placeId).get();
          if (globalDoc.exists) {
            placeResolved = true;
            googlePlaceId = globalDoc.data().googlePlaceId || googlePlaceId;
            globalPlaceId = globalDoc.id;
          }
        }
      } catch (lookupError) {
        console.error('⚠️ Claimability lookup failed:', lookupError.message);
      }

      const claim = { canClaim: placeResolved || !!googlePlaceId, myClaimStatus: null };
      if (claim.canClaim) {
        try {
          const placeKey = globalPlaceId || googlePlaceId || req.params.placeId;
          const claimDoc = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
            .doc(sanitizeKeyPart(`place_${placeKey}_${userId}`)).get();
          if (claimDoc.exists) claim.myClaimStatus = claimDoc.data().status;
        } catch (claimError) {
          console.error('⚠️ Claim status lookup failed:', claimError.message);
        }
      }
      return res.json({ success: true, data: { venue: null, claim } });
    }

    const isOwner = (!!venue.ownerUserId && venue.ownerUserId === userId)
      || req.user.isSuperUser === true;

    // Claim state only matters while the venue is unowned
    let claim = { canClaim: false, myClaimStatus: null };
    if (!venue.ownerUserId) {
      claim.canClaim = true;
      try {
        const claimDoc = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`)).get();
        if (claimDoc.exists) claim.myClaimStatus = claimDoc.data().status;
      } catch (error) {
        console.error('⚠️ Claim status lookup failed:', error.message);
      }
    }

    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : {};
    const balance = userData.rewardPoints || 0;
    // Per-store loyalty: what the caller can actually spend HERE
    const venueBalance = rewardService.venuePointsFrom(userData, venue.venueId);

    // While the owner's business subscription is lapsed (and the venue isn't
    // comped), both offers AND announcements hide — a lapsed owner shouldn't
    // keep broadcasting a paid feature.
    const venueLoyaltyLive = await isVenueLoyaltyActive(venue);

    res.json({
      success: true,
      data: {
        venue: {
          ...publicVenueInfo(venue),
          earnRate: rewardService.effectiveEarnRate(venue)
        },
        offers: (venueLoyaltyLive ? activeOffers(venue) : []).map(({ offerId, title, pointsCost }) => ({
          offerId, title, pointsCost
        })),
        announcements: venueLoyaltyLive ? rewardService.activeAnnouncements(venue) : [],
        balance,
        venueBalance,
        isOwner,
        // For the owner viewing their own place: drives the in-place
        // "Upgrade to Business" teaser when they can't post announcements yet
        ownerPremium: isOwner ? isOwnerPremiumForVenue(req.user, venue.venueId, venue) : undefined,
        // Inline stat strip on the owner's place page (headline counters only)
        ownerStats: isOwner ? {
          saves: (venue.stats || {}).saves || 0,
          visits: (venue.stats || {}).visits || 0,
          scans: (venue.stats || {}).scans || 0,
          redemptions: (venue.stats || {}).redemptions || 0
        } : undefined,
        claim
      }
    });
  } catch (error) {
    console.error('❌ Failed to load venue for place:', error);
    res.status(500).json({ success: false, error: 'Failed to load venue rewards' });
  }
};

// ---------- Super user endpoints (in-app venue management) ----------

// @desc    Current user's rewards profile (drives super-user and venue-owner
//          UI in the app)
// @route   GET /api/rewards/me
// @access  Private
exports.getMe = async (req, res) => {
  let ownsVenues = false;
  try {
    const venuesRef = db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
    const ownedHit = await venuesRef
      .where('ownerUserId', '==', req.user.uid).limit(1).get();
    ownsVenues = !ownedHit.empty;

    // Venue enrolled before the owner signed up: unclaimed email match counts
    // (getMyVenues performs the actual claim)
    if (!ownsVenues && req.user.email) {
      const emailHit = await venuesRef
        .where('ownerEmail', '==', req.user.email.toLowerCase()).limit(5).get();
      ownsVenues = emailHit.docs.some((doc) => !doc.data().ownerUserId);
    }
  } catch (error) {
    console.error('⚠️ ownsVenues lookup failed:', error.message);
  }

  res.json({
    success: true,
    data: {
      isSuperUser: req.user.isSuperUser === true,
      ownsVenues,
      // Account-level "any business entitlement" (summary only) — per-venue
      // gating comes from each venue's own ownerPremium flag
      ownerPremium: isOwnerPremiumUser(req.user),
      ownerPremiumVenueId: req.user.ownerSubscriptionVenueId || null,
      // Brand storefront configured on this account (drives the profile card
      // + edit entry in the app)
      hasStorefront: !!(req.user.storefront && req.user.storefront.enabled),
      email: req.user.email || null
    }
  });
};

// @desc    Create a venue from the app; QR codes are emailed to the requester
// @route   POST /api/rewards/venues
// @access  Super user
exports.createVenueFromApp = async (req, res) => {
  try {
    const payload = { ...req.body };

    // Phone place pickers (MapKit) don't have Google IDs — resolve one so
    // place saves can be attributed to this venue
    if (!payload.googlePlaceId && !payload.globalPlaceId) {
      payload.googlePlaceId = await rewardService.resolveGooglePlaceId(
        payload.venueName,
        payload.placeAddress,
        payload.location?.lat,
        payload.location?.lng
      );
    }

    const errors = validateStickerVenue(payload);
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const venue = await rewardService.createVenue(payload);

    let emailSent = false;
    const toEmail = req.user.email;
    if (toEmail) {
      try {
        const { windowQR, registerQR } = await rewardService.generateQRBuffers(venue);
        await emailService.sendStickerQREmail(toEmail, venue, windowQR, registerQR);
        emailSent = true;
      } catch (error) {
        console.error('⚠️ QR email failed (venue still created):', error.message);
      }
    }

    res.status(201).json({
      success: true,
      data: {
        venueId: venue.venueId,
        venueName: venue.venueName,
        windowCode: venue.windowCode,
        registerCode: venue.registerCode,
        windowStickerUrl: rewardService.stickerUrl(venue.windowCode),
        registerCardUrl: rewardService.stickerUrl(venue.registerCode),
        googlePlaceId: venue.googlePlaceId,
        offers: venue.offers,
        emailSent,
        emailedTo: emailSent ? toEmail : null
      }
    });
  } catch (error) {
    console.error('❌ In-app venue creation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to create venue' });
  }
};

// @desc    Re-send a venue's QR codes to the requesting super user
// @route   POST /api/rewards/venues/:venueId/email-qr
// @access  Super user
exports.emailVenueQR = async (req, res) => {
  try {
    const toEmail = req.user.email;
    if (!toEmail) {
      return res.status(400).json({ success: false, error: 'Your account has no email address' });
    }

    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.params.venueId).get();
    if (!venueDoc.exists) {
      return res.status(404).json({ success: false, error: 'Venue not found' });
    }

    const venue = { venueId: venueDoc.id, ...venueDoc.data() };
    const { windowQR, registerQR } = await rewardService.generateQRBuffers(venue);
    await emailService.sendStickerQREmail(toEmail, venue, windowQR, registerQR);

    res.json({ success: true, data: { emailedTo: toEmail } });
  } catch (error) {
    console.error('❌ QR re-send failed:', error);
    res.status(500).json({ success: false, error: 'Failed to email QR codes' });
  }
};

// @desc    Grant or revoke super-user status by email
// @route   POST /api/rewards/superusers
// @access  Super user
exports.setSuperUser = async (req, res) => {
  try {
    const { email, isSuperUser } = req.body;
    if (!email || typeof isSuperUser !== 'boolean') {
      return res.status(400).json({ success: false, error: 'email and isSuperUser (boolean) are required' });
    }

    const normalizedEmail = String(email).trim().toLowerCase();

    if (!isSuperUser && normalizedEmail === (req.user.email || '').toLowerCase()) {
      return res.status(400).json({ success: false, error: "You can't revoke your own super-user access" });
    }

    const snapshot = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', normalizedEmail)
      .limit(1)
      .get();
    if (snapshot.empty) {
      return res.status(404).json({ success: false, error: `No user found with email ${normalizedEmail}` });
    }

    await snapshot.docs[0].ref.update({ isSuperUser });

    res.json({
      success: true,
      data: {
        email: normalizedEmail,
        isSuperUser,
        message: isSuperUser
          ? `${normalizedEmail} can now sign up venues for the sticker program`
          : `Super-user access removed for ${normalizedEmail}`
      }
    });
  } catch (error) {
    console.error('❌ setSuperUser failed:', error);
    res.status(500).json({ success: false, error: 'Failed to update super-user status' });
  }
};

// ---------- Venue owner endpoints (self-service offer/earn-rate management) ----------

// What an owner sees about their own venue: everything except internals.
// Owners legitimately hold their codes — they print and display them.
const ownerVenueInfo = (venue) => ({
  venueId: venue.venueId,
  venueName: venue.venueName,
  placeName: venue.placeName,
  placeAddress: venue.placeAddress,
  category: venue.category || 'restaurant',
  contactName: venue.contactName || null,
  contactEmail: venue.contactEmail || null,
  googlePlaceId: venue.googlePlaceId,
  globalPlaceId: venue.globalPlaceId,
  location: venue.location || null,
  isVirtual: venue.isVirtual === true,
  windowCode: venue.windowCode,
  registerCode: venue.registerCode,
  // Exact URL encoded in the printed window sticker, so the in-app QR
  // renders identically to the physical one
  windowStickerUrl: rewardService.stickerUrl(venue.windowCode),
  earnRate: rewardService.effectiveEarnRate(venue),
  offers: venue.offers || [],
  announcements: venue.announcements || [],
  stats: venue.stats || {},
  createdAt: venue.createdAt
});

// Route middleware: loads req.venue and allows the venue's owner or any
// super-user through.
exports.requireVenueOwner = async (req, res, next) => {
  try {
    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.params.venueId).get();
    if (!venueDoc.exists) {
      return res.status(404).json({ success: false, error: 'Venue not found' });
    }
    const venue = { venueId: venueDoc.id, ...venueDoc.data() };
    const isOwner = !!venue.ownerUserId && venue.ownerUserId === req.user.uid;
    if (!isOwner && req.user.isSuperUser !== true) {
      return res.status(403).json({ success: false, error: 'You do not manage this venue' });
    }
    req.venue = venue;
    next();
  } catch (error) {
    console.error('❌ Venue owner check failed:', error);
    res.status(500).json({ success: false, error: 'Failed to verify venue access' });
  }
};

// @desc    Venues the current user owns. Lazily claims venues that were
//          enrolled with this user's email before they had an account.
// @route   GET /api/rewards/my-venues
// @access  Private
exports.getMyVenues = async (req, res) => {
  try {
    const uid = req.user.uid;
    const venuesRef = db.collection(STICKER_COLLECTIONS.STICKER_VENUES);

    const snapshot = await venuesRef.where('ownerUserId', '==', uid).get();
    let venues = snapshot.docs.map((doc) => ({ venueId: doc.id, ...doc.data() }));

    if (venues.length === 0 && req.user.email) {
      const emailHit = await venuesRef
        .where('ownerEmail', '==', req.user.email.toLowerCase()).get();
      const claimable = emailHit.docs.filter((doc) => !doc.data().ownerUserId);
      await Promise.all(claimable.map((doc) => doc.ref.update({
        ownerUserId: uid,
        updatedAt: new Date().toISOString()
      })));
      venues = claimable.map((doc) => ({ venueId: doc.id, ...doc.data(), ownerUserId: uid }));
    }

    // Follower counts ride along so venue list rows can show them; the
    // subscription only covers one venue, so premium is stamped per venue.
    const venueInfos = venues.map(ownerVenueInfo);
    venueInfos.forEach((info, i) => {
      info.ownerPremium = isOwnerPremiumForVenue(req.user, venues[i].venueId, venues[i]);
    });
    await Promise.all(venueInfos.map(async (info, i) => {
      const globalPlaceId = await venueGlobalPlaceId(venues[i]);
      if (!globalPlaceId) return;
      const globalDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
        .doc(globalPlaceId).get();
      info.stats = {
        ...info.stats,
        followers: (globalDoc.exists && globalDoc.data().followersCount) || 0
      };
    }));

    res.json({
      success: true,
      data: {
        venues: venueInfos,
        count: venues.length,
        // Legacy account-level flag (older builds gate on this; the server
        // enforces per venue regardless)
        ownerPremium: isOwnerPremiumUser(req.user)
      }
    });
  } catch (error) {
    console.error('❌ Failed to load owned venues:', error);
    res.status(500).json({ success: false, error: 'Failed to load your venues' });
  }
};

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

// Fire-and-forget activity for venue announcements/offers so they surface in
// followers' feeds. Actor id 'place_<globalPlaceId>' — the feed query adds a
// user's followed places under the same key, and enrichment synthesizes a
// place actor. Venues with no resolvable global place just skip emission.
// Live-refresh signal for the home screen's Specials tab: any change to a
// venue's offers or announcements pushes every connected client to refetch
const notifySpecialsChanged = (venueId) => {
  try {
    sseService.broadcast('specials_updated', { venueId });
  } catch (error) {
    console.error('⚠️ specials_updated broadcast failed:', error.message);
  }
};

const emitVenueActivity = (venue, type, message) => {
  (async () => {
    try {
      const globalPlaceId = await venueGlobalPlaceId(venue);
      if (!globalPlaceId) return;
      await createActivity(
        type,
        `place_${globalPlaceId}`,
        'place',
        globalPlaceId,
        venue.placeName || venue.venueName,
        {
          message,
          placeId: globalPlaceId,
          placeAddress: venue.placeAddress || null
        }
      );
    } catch (error) {
      console.error('⚠️ Venue activity emission failed:', error.message);
    }
  })();
};

// @desc    Per-venue stats dashboard. Headline counts are visible to every
//          claimed owner (they're the upsell); detail requires the business
//          subscription.
// @route   GET /api/rewards/venues/:venueId/dashboard
// @access  Venue owner (or super user)
exports.getVenueDashboard = async (req, res) => {
  try {
    const venue = req.venue;
    const premiumActive = isOwnerPremiumForVenue(req.user, venue.venueId, venue);
    const globalPlaceId = await venueGlobalPlaceId(venue);

    // Followers live on the canonical globalPlaces record
    let followersCount = 0;
    if (globalPlaceId) {
      const globalDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
        .doc(globalPlaceId).get();
      followersCount = (globalDoc.exists && globalDoc.data().followersCount) || 0;
    }

    // Organic saves = thin save docs referencing the venue, distinct by saver.
    // Projection query keeps this cheap; equality-only, so no composite index.
    let saveDocs = [];
    if (globalPlaceId) {
      const savesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('globalPlaceId', '==', globalPlaceId)
        .where('deletedAt', '==', null)
        .select('addedBy', 'createdAt')
        .get();
      saveDocs = savesSnapshot.docs.map((doc) => doc.data());
    }
    const distinctSavers = new Set(saveDocs.map((d) => d.addedBy).filter(Boolean));

    const stats = venue.stats || {};
    const headline = {
      saves: distinctSavers.size,
      followers: followersCount,
      visits: stats.visits || 0,
      scans: stats.scans || 0,
      signups: stats.signups || 0,
      redemptions: stats.redemptions || 0,
      codeRedemptions: stats.codeRedemptions || 0,
      // App Clip funnel (scan → in-clip signup → full-app install)
      clipScans: stats.clipScans || 0,
      clipSignups: stats.clipSignups || 0,
      clipInstalls: stats.clipInstalls || 0
    };

    let detail = null;
    if (premiumActive) {
      // Last 6 months of the venue's counter history, newest first
      const monthly = {};
      const now = new Date();
      for (let i = 0; i < 6; i++) {
        const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
        const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
        monthly[key] = (venue.statsMonthly || {})[key] || {};
      }

      const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
      const newSavesThisMonth = saveDocs.filter(
        (d) => d.createdAt && d.createdAt >= monthStart
      ).length;

      detail = { monthly, newSavesThisMonth };
    }

    res.json({
      success: true,
      data: {
        venueId: venue.venueId,
        venueName: venue.venueName,
        premium: { active: premiumActive },
        headline,
        detail
      }
    });
  } catch (error) {
    console.error('❌ Failed to load venue dashboard:', error);
    res.status(500).json({ success: false, error: 'Failed to load venue dashboard' });
  }
};

// Batch-load user docs in getAll-sized chunks and project the public card
// fields. Never leaks email; these lists render inside the owner dashboard.
const loadUserCards = async (userIds) => {
  const cards = new Map();
  const ids = [...new Set(userIds)].filter(Boolean);
  for (let i = 0; i < ids.length; i += 100) {
    const refs = ids.slice(i, i + 100).map((id) => db.collection(COLLECTIONS.USERS).doc(id));
    const docs = await db.getAll(...refs);
    docs.forEach((doc) => {
      if (!doc.exists) return;
      const u = doc.data();
      cards.set(doc.id, {
        id: doc.id,
        displayName: u.displayName || 'FavCircles user',
        username: u.username || null,
        profilePicture: u.profilePicture || null
      });
    });
  }
  return cards;
};

// @desc    Who follows this venue's place. Following a store is a directed
//          act toward the business, so the full list is visible to the owner.
// @route   GET /api/rewards/venues/:venueId/followers
// @access  Venue owner + business tier
exports.getVenueFollowers = async (req, res) => {
  try {
    const venue = req.venue;
    const globalPlaceId = await venueGlobalPlaceId(venue);
    let followerIds = [];
    if (globalPlaceId) {
      const gpDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).get();
      followerIds = (gpDoc.exists && gpDoc.data().followers) || [];
    }
    const cards = await loadUserCards(followerIds);
    res.json({
      success: true,
      data: {
        count: followerIds.length,
        followers: followerIds.map((id) => cards.get(id)).filter(Boolean)
      }
    });
  } catch (error) {
    console.error('❌ Failed to load venue followers:', error);
    res.status(500).json({ success: false, error: 'Failed to load venue followers' });
  }
};

// @desc    Who saved this venue's place. The COUNT includes everyone; the
//          identity list includes only savers whose save would already be
//          visible to the owner browsing as a regular user — public circles,
//          shared-with, or myNetwork circles of a connection — and never a
//          save marked place-private. Saving is the user organizing their own
//          places, not a message to the store, so private stays private.
// @route   GET /api/rewards/venues/:venueId/savers
// @access  Venue owner + business tier
exports.getVenueSavers = async (req, res) => {
  try {
    const venue = req.venue;
    const ownerId = req.user.uid;
    const globalPlaceId = await venueGlobalPlaceId(venue);
    if (!globalPlaceId) {
      return res.json({ success: true, data: { totalCount: 0, count: 0, savers: [] } });
    }

    const snapshot = await db.collection(COLLECTIONS.PLACES)
      .where('globalPlaceId', '==', globalPlaceId)
      .where('deletedAt', '==', null)
      .select('addedBy', 'circleId', 'privacy', 'createdAt')
      .get();

    // Group saves by saver: circles their copies live in, earliest save date,
    // and whether ANY copy escapes place-private
    const bySaver = new Map();
    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const saverId = normalizeUserId(data.addedBy);
      if (!saverId) return;
      const entry = bySaver.get(saverId) || { circleIds: new Set(), savedAt: null, hasNonPrivate: false };
      if (data.circleId) entry.circleIds.add(data.circleId);
      if (data.privacy !== 'private') entry.hasNonPrivate = true;
      if (data.createdAt && (!entry.savedAt || data.createdAt < entry.savedAt)) entry.savedAt = data.createdAt;
      bySaver.set(saverId, entry);
    });

    const totalCount = bySaver.size;
    if (totalCount === 0) {
      return res.json({ success: true, data: { totalCount: 0, count: 0, savers: [] } });
    }

    // Circle visibility from the OWNER's viewpoint (same rules as the
    // consumer savers list in firebasePlaceController.getPlaceSavers)
    const circleIds = [...new Set([...bySaver.values()].flatMap((e) => [...e.circleIds]))];
    const circlesById = new Map();
    for (let i = 0; i < circleIds.length; i += 100) {
      const refs = circleIds.slice(i, i + 100).map((id) => db.collection(COLLECTIONS.CIRCLES).doc(id));
      const docs = await db.getAll(...refs);
      docs.forEach((doc) => { if (doc.exists) circlesById.set(doc.id, doc.data()); });
    }

    const [outgoing, incomingAccepted] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', ownerId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', ownerId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    const connectedIds = new Set();
    outgoing.forEach((doc) => connectedIds.add(normalizeUserId(doc.data().connectedUserId)));
    incomingAccepted.forEach((doc) => connectedIds.add(normalizeUserId(doc.data().userId)));

    const isCircleVisibleToOwner = (circle, saverId) => {
      if (!circle) return false;
      if (isSameUser(saverId, ownerId) || isSameUser(circle.owner, ownerId)) return true;
      if (circle.privacy === 'public') return true;
      if (circle.sharedWith && circle.sharedWith.includes(ownerId)) return true;
      if (circle.privacy === 'myNetwork' && connectedIds.has(normalizeUserId(circle.owner))) return true;
      return false;
    };

    const visible = [...bySaver.entries()].filter(([saverId, entry]) =>
      entry.hasNonPrivate &&
      [...entry.circleIds].some((circleId) => isCircleVisibleToOwner(circlesById.get(circleId), saverId)));

    const cards = await loadUserCards(visible.map(([id]) => id));
    const savers = visible
      .map(([id, entry]) => {
        const card = cards.get(id);
        return card ? { ...card, savedAt: entry.savedAt } : null;
      })
      .filter(Boolean)
      .sort((a, b) => (b.savedAt || '').localeCompare(a.savedAt || ''));

    res.json({
      success: true,
      data: { totalCount, count: savers.length, savers }
    });
  } catch (error) {
    console.error('❌ Failed to load venue savers:', error);
    res.status(500).json({ success: false, error: 'Failed to load venue savers' });
  }
};

// @desc    The venue's loyalty ledger: scans, sign-ups, saves, redemptions —
//          each with who and when. Scanning the store's QR is a physical
//          interaction with the business (a digital punch card), so the owner
//          sees their own ledger. Client renders histograms from timestamps.
// @route   GET /api/rewards/venues/:venueId/activity?limit=&before=
// @access  Venue owner + business tier
exports.getVenueActivity = async (req, res) => {
  try {
    const venue = req.venue;
    const limit = Math.min(parseInt(req.query.limit, 10) || 200, 500);

    let query = db.collection(STICKER_COLLECTIONS.REWARD_EVENTS)
      .where('venueId', '==', venue.venueId)
      .orderBy('createdAt', 'desc')
      .limit(limit);
    if (req.query.before) {
      query = query.startAfter(String(req.query.before));
    }
    const snapshot = await query.get();

    const cards = await loadUserCards(snapshot.docs.map((d) => d.data().userId));
    const events = snapshot.docs.map((doc) => {
      const e = doc.data();
      return {
        id: doc.id,
        type: e.type,
        points: e.points || 0,
        createdAt: e.createdAt,
        offerTitle: e.offerTitle || null,
        user: cards.get(e.userId) || null
      };
    });

    res.json({
      success: true,
      data: {
        events,
        nextBefore: events.length === limit ? events[events.length - 1].createdAt : null
      }
    });
  } catch (error) {
    console.error('❌ Failed to load venue activity:', error);
    res.status(500).json({ success: false, error: 'Failed to load venue activity' });
  }
};

// @desc    Set (or clear) the venue's cover photo. The URL must be one of the
//          canonical place's existing photos — the owner curates, they don't
//          bypass the media pipeline. Stored on the globalPlaces doc so every
//          surface (place page carousel, offers list) can honor it.
// @route   PUT /api/rewards/venues/:venueId/cover-photo   body: { url|null }
// @access  Venue owner (or super user)
exports.setVenueCoverPhoto = async (req, res) => {
  try {
    const venue = req.venue;
    const url = req.body.url === null || req.body.url === undefined
      ? null : String(req.body.url);
    const globalPlaceId = await venueGlobalPlaceId(venue);
    if (!globalPlaceId) {
      return res.status(400).json({ success: false, error: 'This venue has no linked place record' });
    }
    const gpRef = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId);
    if (url) {
      const gpDoc = await gpRef.get();
      const photos = (gpDoc.exists && gpDoc.data().photos) || [];
      const known = photos.some((p) => (typeof p === 'string' ? p : p && p.url) === url);
      if (!known) {
        return res.status(400).json({ success: false, error: 'Cover photo must be one of the place\'s photos' });
      }
    }
    await gpRef.set({ coverPhotoUrl: url, updatedAt: new Date().toISOString() }, { merge: true });
    res.json({ success: true, data: { coverPhotoUrl: url } });
  } catch (error) {
    console.error('❌ Failed to set venue cover photo:', error);
    res.status(500).json({ success: false, error: 'Failed to set cover photo' });
  }
};

// @desc    Email the caller the ChatGPT/Claude connector setup guide. Any
//          user who owns at least one venue qualifies (the setup happens on
//          their computer in the assistant's settings, so a durable email
//          beats in-app text).
// @route   POST /api/rewards/email-ai-setup
// @access  Private (venue owners)
exports.emailAiSetup = async (req, res) => {
  try {
    const uid = req.user.uid;
    const owned = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .where('ownerUserId', '==', uid).limit(1).get();
    if (owned.empty && req.user.isSuperUser !== true) {
      return res.status(403).json({ success: false, error: 'Only store owners can request the AI setup guide' });
    }

    const userDoc = await db.collection(COLLECTIONS.USERS).doc(uid).get();
    const user = userDoc.exists ? userDoc.data() : {};
    const toEmail = user.email || req.user.email;
    if (!toEmail) {
      return res.status(400).json({ success: false, error: 'No email address on your account' });
    }

    await emailService.sendAiSetupEmail(toEmail, user.displayName || null);
    res.json({ success: true, data: { emailedTo: toEmail } });
  } catch (error) {
    console.error('❌ Failed to send AI setup email:', error);
    res.status(500).json({ success: false, error: 'Failed to send the setup email' });
  }
};

// @desc    Owner edit of the venue's canonical place record (name,
//          description, category, phone, website) — no personal save doc
//          needed, unlike PUT /api/places/:id. Writes the globalPlaces doc
//          once and fans cache fields to every saver's copy. Built for the
//          MCP store-owner tools; address deliberately excluded (address
//          changes need the geocode-confirmed flow).
// @route   PATCH /api/rewards/venues/:venueId/place
// @access  Venue owner (or super user)
exports.updateVenuePlace = async (req, res) => {
  try {
    const venue = req.venue;
    const globalPlaceId = await venueGlobalPlaceId(venue);
    if (!globalPlaceId) {
      return res.status(400).json({ success: false, error: 'This venue has no linked place record' });
    }

    const { name, description, category, phone, website, openingHours } = req.body;
    const VALID_CATEGORIES = ['restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction',
      'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 'transport', 'finance', 'other'];

    const updates = {};
    if (typeof name === 'string' && name.trim()) updates.name = name.trim();
    if (typeof description === 'string') {
      // Description is prose — contact data lives in its own fields
      updates.description = description
        .split('\n')
        .filter((line) => !/^\s*(Phone|Website):/i.test(line))
        .join('\n')
        .trim();
    }
    if (typeof category === 'string' && category) {
      if (!VALID_CATEGORIES.includes(category)) {
        return res.status(400).json({ success: false, error: `Invalid category. Valid: ${VALID_CATEGORIES.join(', ')}` });
      }
      updates.category = category;
    }
    if (typeof phone === 'string') updates['googleData.phone'] = phone.trim();
    if (typeof website === 'string') updates['googleData.website'] = website.trim();

    // Owner-set hours REPLACE the stored week, in the exact shape the iOS
    // place page renders: [{day 0=Sunday..6, open "HH:MM", close, isClosed}]
    if (openingHours !== undefined) {
      if (!Array.isArray(openingHours) || openingHours.length === 0) {
        return res.status(400).json({ success: false, error: 'openingHours must be a non-empty array of {day, open, close, isClosed}' });
      }
      const timeRe = /^([01]?\d|2[0-3]):[0-5]\d$/;
      const hourErrors = [];
      const cleaned = [];
      const seenDays = new Set();
      openingHours.forEach((h, i) => {
        const day = Number(h && h.day);
        if (!Number.isInteger(day) || day < 0 || day > 6) {
          hourErrors.push(`entry ${i}: day must be 0 (Sunday) through 6 (Saturday)`);
          return;
        }
        if (seenDays.has(day)) {
          hourErrors.push(`entry ${i}: duplicate day ${day}`);
          return;
        }
        seenDays.add(day);
        const isClosed = h.isClosed === true;
        if (!isClosed && (!timeRe.test(h.open || '') || !timeRe.test(h.close || ''))) {
          hourErrors.push(`entry ${i}: open/close must be 24h "HH:MM" unless isClosed is true`);
          return;
        }
        cleaned.push({ day, open: isClosed ? null : h.open, close: isClosed ? null : h.close, isClosed });
      });
      if (hourErrors.length > 0) {
        return res.status(400).json({ success: false, error: hourErrors.join('; ') });
      }
      updates['googleData.openingHours'] = cleaned.sort((a, b) => a.day - b.day);
      // Owner-set hours must survive any future Google-data refresh
      updates['googleData.hoursSource'] = 'owner';
    }

    if (Object.keys(updates).length === 0) {
      return res.status(400).json({ success: false, error: 'Nothing to update — provide name, description, category, phone, website, or openingHours' });
    }

    if (updates.name) {
      const { buildSearchTokens } = require('../models/GlobalPlace');
      updates.nameLower = updates.name.toLowerCase();
      updates.searchTokens = buildSearchTokens(updates.name);
    }
    updates.updatedAt = new Date().toISOString();

    const gpRef = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId);
    await gpRef.update(updates);

    // Fan denormalized query-cache fields out to every save doc
    const cacheUpdates = {};
    if (updates.name) cacheUpdates.name = updates.name;
    if (updates.category) cacheUpdates.category = updates.category;
    if (Object.keys(cacheUpdates).length > 0) {
      const savesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('globalPlaceId', '==', globalPlaceId).get();
      const batch = db.batch();
      savesSnapshot.docs.forEach((doc) => batch.update(doc.ref, cacheUpdates));
      await batch.commit();
      // Keep the venue's own place-name cache in step (venueName — the
      // store's brand name in the rewards program — stays owner-controlled)
      if (updates.name) {
        await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
          .doc(venue.venueId).update({ placeName: updates.name, updatedAt: new Date().toISOString() });
      }
    }

    const gpDoc = await gpRef.get();
    const g = gpDoc.data();
    res.json({
      success: true,
      data: {
        globalPlaceId,
        name: g.name,
        description: g.description || null,
        category: g.category || null,
        phone: (g.googleData || {}).phone || null,
        website: (g.googleData || {}).website || null,
        openingHours: (g.googleData || {}).openingHours || null
      }
    });
  } catch (error) {
    console.error('❌ Failed to update venue place:', error);
    res.status(500).json({ success: false, error: 'Failed to update store details' });
  }
};

// @desc    Add an offer to a venue
// @route   POST /api/rewards/venues/:venueId/offers
// @access  Venue owner (or super user)
exports.addOffer = async (req, res) => {
  try {
    const { title, pointsCost } = req.body;
    const errors = [];
    if (title === undefined) errors.push('title is required');
    if (pointsCost === undefined) errors.push('pointsCost is required');
    errors.push(...validateOfferInput({ title, pointsCost }));
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const offers = [...(req.venue.offers || [])];
    offers.push({
      // Timestamp-based id — index-based ids collide once offers get removed
      offerId: `offer_${Date.now()}`,
      title: String(title).trim(),
      pointsCost,
      active: true
    });

    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.venue.venueId)
      .update({ offers, updatedAt: new Date().toISOString() });

    emitVenueActivity(req.venue, 'venue_offer', String(title).trim());
    notifySpecialsChanged(req.venue.venueId);

    res.status(201).json({ success: true, data: { offers } });
  } catch (error) {
    console.error('❌ Failed to add offer:', error);
    res.status(500).json({ success: false, error: 'Failed to add offer' });
  }
};

// @desc    Edit an offer's title, point cost, or active flag
// @route   PUT /api/rewards/venues/:venueId/offers/:offerId
// @access  Venue owner (or super user)
exports.updateOffer = async (req, res) => {
  try {
    const { title, pointsCost, active } = req.body;
    const errors = validateOfferInput({ title, pointsCost });
    if (active !== undefined && typeof active !== 'boolean') {
      errors.push('active must be a boolean');
    }
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const offers = [...(req.venue.offers || [])];
    const index = offers.findIndex((o) => o.offerId === req.params.offerId);
    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Offer not found' });
    }

    offers[index] = {
      ...offers[index],
      ...(title !== undefined && { title: String(title).trim() }),
      ...(pointsCost !== undefined && { pointsCost }),
      ...(active !== undefined && { active })
    };

    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.venue.venueId)
      .update({ offers, updatedAt: new Date().toISOString() });

    notifySpecialsChanged(req.venue.venueId);
    res.json({ success: true, data: { offers } });
  } catch (error) {
    console.error('❌ Failed to update offer:', error);
    res.status(500).json({ success: false, error: 'Failed to update offer' });
  }
};

// Announcements expired this long ago get pruned on the next write, keeping
// the embedded array (and the venue doc) small permanently.
const PRUNE_EXPIRED_AFTER_MS = 30 * 24 * 60 * 60 * 1000;

const pruneStaleAnnouncements = (announcements) => {
  const cutoff = Date.now() - PRUNE_EXPIRED_AFTER_MS;
  return announcements.filter((a) => !a.expiresAt || new Date(a.expiresAt).getTime() > cutoff);
};

const saveAnnouncements = async (venueId, announcements) => {
  await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
    .doc(venueId)
    .update({ announcements, updatedAt: new Date().toISOString() });
};

// @desc    Post an announcement to the venue's place page
// @route   POST /api/rewards/venues/:venueId/announcements
// @access  Venue owner (or super user)
exports.addAnnouncement = async (req, res) => {
  try {
    const { title, message, expiresAt } = req.body;
    const errors = [];
    if (title === undefined) errors.push('title is required');
    if (message === undefined) errors.push('message is required');
    errors.push(...validateAnnouncementInput({ title, message, expiresAt }));
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const announcements = pruneStaleAnnouncements([...(req.venue.announcements || [])]);
    if (announcements.length >= MAX_ANNOUNCEMENTS) {
      return res.status(400).json({
        success: false,
        error: `A venue can have at most ${MAX_ANNOUNCEMENTS} announcements — delete one first`
      });
    }

    const now = new Date().toISOString();
    announcements.push({
      announcementId: `ann_${Date.now()}`,
      title: String(title).trim(),
      message: String(message).trim(),
      expiresAt: expiresAt || null,
      createdAt: now,
      updatedAt: now
    });

    await saveAnnouncements(req.venue.venueId, announcements);

    emitVenueActivity(req.venue, 'venue_announcement', String(title).trim());
    notifySpecialsChanged(req.venue.venueId);

    res.status(201).json({ success: true, data: { announcements } });
  } catch (error) {
    console.error('❌ Failed to add announcement:', error);
    res.status(500).json({ success: false, error: 'Failed to add announcement' });
  }
};

// @desc    Edit an announcement's title, message, or expiry
//          (pass expiresAt: null to clear the expiry)
// @route   PUT /api/rewards/venues/:venueId/announcements/:announcementId
// @access  Venue owner (or super user)
exports.updateAnnouncement = async (req, res) => {
  try {
    const { title, message, expiresAt } = req.body;
    const errors = validateAnnouncementInput({ title, message, expiresAt });
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const announcements = [...(req.venue.announcements || [])];
    const index = announcements.findIndex((a) => a.announcementId === req.params.announcementId);
    if (index === -1) {
      return res.status(404).json({ success: false, error: 'Announcement not found' });
    }

    announcements[index] = {
      ...announcements[index],
      ...(title !== undefined && { title: String(title).trim() }),
      ...(message !== undefined && { message: String(message).trim() }),
      ...(expiresAt !== undefined && { expiresAt: expiresAt || null }),
      updatedAt: new Date().toISOString()
    };

    await saveAnnouncements(req.venue.venueId, announcements);
    notifySpecialsChanged(req.venue.venueId);
    res.json({ success: true, data: { announcements } });
  } catch (error) {
    console.error('❌ Failed to update announcement:', error);
    res.status(500).json({ success: false, error: 'Failed to update announcement' });
  }
};

// @desc    Delete an announcement
// @route   DELETE /api/rewards/venues/:venueId/announcements/:announcementId
// @access  Venue owner (or super user)
exports.deleteAnnouncement = async (req, res) => {
  try {
    const before = req.venue.announcements || [];
    const announcements = before.filter((a) => a.announcementId !== req.params.announcementId);
    if (announcements.length === before.length) {
      return res.status(404).json({ success: false, error: 'Announcement not found' });
    }

    await saveAnnouncements(req.venue.venueId, announcements);
    notifySpecialsChanged(req.venue.venueId);
    res.json({ success: true, data: { announcements } });
  } catch (error) {
    console.error('❌ Failed to delete announcement:', error);
    res.status(500).json({ success: false, error: 'Failed to delete announcement' });
  }
};

// @desc    Update the venue's business contact info (free owner tier —
//          unlike updateVenueSettings, no business subscription required)
// @route   PATCH /api/rewards/venues/:venueId/info
// @access  Venue owner (or super user)
exports.updateVenueInfo = async (req, res) => {
  try {
    const { contactName, contactEmail } = req.body;
    const errors = [];
    if (contactName !== undefined && typeof contactName !== 'string') {
      errors.push('contactName must be a string');
    }
    if (contactEmail !== undefined) {
      if (typeof contactEmail !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail.trim())) {
        errors.push('contactEmail must be a valid email address');
      }
    }
    if (contactName === undefined && contactEmail === undefined) {
      errors.push('Nothing to update');
    }
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const update = { updatedAt: new Date().toISOString() };
    if (contactName !== undefined) update.contactName = String(contactName).trim() || null;
    if (contactEmail !== undefined) {
      update.contactEmail = contactEmail.trim().toLowerCase();
      // ownerEmail mirrors contactEmail (used for lazy claim-by-email)
      update.ownerEmail = update.contactEmail;
    }

    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.venue.venueId)
      .update(update);

    res.json({ success: true, data: { venue: ownerVenueInfo({ ...req.venue, ...update }) } });
  } catch (error) {
    console.error('❌ Failed to update venue info:', error);
    res.status(500).json({ success: false, error: 'Failed to update venue info' });
  }
};

// @desc    Adjust venue settings (points per purchase)
// @route   PATCH /api/rewards/venues/:venueId
// @access  Venue owner (or super user)
exports.updateVenueSettings = async (req, res) => {
  try {
    const { earnRate } = req.body;
    const errors = validateEarnRate(earnRate);
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.venue.venueId)
      .update({ earnRate, updatedAt: new Date().toISOString() });

    res.json({ success: true, data: { venueId: req.venue.venueId, earnRate } });
  } catch (error) {
    console.error('❌ Failed to update venue settings:', error);
    res.status(500).json({ success: false, error: 'Failed to update venue settings' });
  }
};

// @desc    Rotate the register QR code (invalidates the old one immediately),
//          optionally binding a new earn rate to the fresh code
// @route   POST /api/rewards/venues/:venueId/register-code
// @access  Venue owner (or super user)
exports.rotateRegisterCode = async (req, res) => {
  try {
    const { earnRate } = req.body || {};
    if (earnRate !== undefined) {
      const errors = validateEarnRate(earnRate);
      if (errors.length > 0) {
        return res.status(400).json({ success: false, error: errors.join('. ') });
      }
    }

    const registerCode = await rewardService.rotateRegisterCode(req.venue, earnRate);

    res.json({
      success: true,
      data: {
        venueId: req.venue.venueId,
        registerCode,
        registerCardUrl: rewardService.stickerUrl(registerCode),
        earnRate: earnRate !== undefined
          ? earnRate
          : rewardService.effectiveEarnRate(req.venue)
      }
    });
  } catch (error) {
    console.error('❌ Register code rotation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to rotate register code' });
  }
};

// @desc    Assign a venue's owner by email
// @route   POST /api/rewards/venues/:venueId/owner
// @access  Super user
exports.setVenueOwner = async (req, res) => {
  try {
    const { email } = req.body;
    if (!email) {
      return res.status(400).json({ success: false, error: 'email is required' });
    }
    const normalizedEmail = String(email).trim().toLowerCase();

    const ownerUserId = await rewardService.resolveOwnerUserId(normalizedEmail);
    if (!ownerUserId) {
      return res.status(404).json({ success: false, error: `No user found with email ${normalizedEmail}` });
    }

    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.params.venueId).get();
    if (!venueDoc.exists) {
      return res.status(404).json({ success: false, error: 'Venue not found' });
    }

    await rewardService.assignVenueOwner(venueDoc.id, { ownerUserId, ownerEmail: normalizedEmail });

    res.json({
      success: true,
      data: { venueId: venueDoc.id, ownerEmail: normalizedEmail }
    });
  } catch (error) {
    console.error('❌ setVenueOwner failed:', error);
    res.status(500).json({ success: false, error: 'Failed to assign venue owner' });
  }
};

// ---------- Ownership claims (filed from a place page) ----------

// Email the admin about a new ownership claim — the approval decision is
// made by a human, so this is the actual verification channel.
const sendClaimAdminEmail = async (claim, claimId) => {
  try {
    const emailService = require('../services/emailService');
    const adminEmail = process.env.ADMIN_EMAIL || 'wesley@favcircles.com';
    const enrolled = !!claim.venueId;
    const businessName = claim.venueName || claim.placeName || 'Unknown business';
    await emailService.sendEmail({
      to: adminEmail,
      subject: `🏪 Ownership claim: ${businessName}`,
      text: [
        `Someone claimed a business on FavCircles.`,
        ``,
        `Business: ${businessName}`,
        `Address: ${claim.placeAddress || 'unknown'}`,
        enrolled
          ? `Sticker venue: ${claim.venueId} (enrolled — approve from the app's claims tray)`
          : `Sticker venue: not enrolled (verify, then enroll the venue and assign this owner)`,
        `Place ID: ${claim.placeId || 'n/a'} · Global: ${claim.globalPlaceId || 'n/a'} · Google: ${claim.googlePlaceId || 'n/a'}`,
        ``,
        `Claimer account: ${claim.userDisplayName || 'unknown'} (${claim.userEmail || claim.userId})`,
        `Contact name: ${claim.contactName || '-'}`,
        `Contact email: ${claim.contactEmail || '-'}`,
        `Contact phone: ${claim.contactPhone || '-'}`,
        `Message: ${claim.message || '-'}`,
        ``,
        `Claim ID: ${claimId}`
      ].join('\n'),
      html: `
        <h2>🏪 Ownership claim: ${businessName}</h2>
        <p><strong>Address:</strong> ${claim.placeAddress || 'unknown'}<br>
        <strong>Sticker venue:</strong> ${enrolled ? `${claim.venueId} (enrolled — approve from the app's claims tray)` : 'not enrolled — verify, then enroll the venue and assign this owner'}<br>
        <strong>Place ID:</strong> ${claim.placeId || 'n/a'} · <strong>Global:</strong> ${claim.globalPlaceId || 'n/a'} · <strong>Google:</strong> ${claim.googlePlaceId || 'n/a'}</p>
        <p><strong>Claimer account:</strong> ${claim.userDisplayName || 'unknown'} (${claim.userEmail || claim.userId})</p>
        <p><strong>Contact:</strong> ${claim.contactName || '-'} · ${claim.contactEmail || '-'} · ${claim.contactPhone || '-'}</p>
        <p><strong>Message:</strong> ${claim.message || '-'}</p>
        <p><em>Claim ID: ${claimId}</em></p>
      `
    });
  } catch (emailError) {
    console.error('⚠️ Claim admin email failed:', emailError.message);
  }
};

// Shared submit: idempotent on the doc id — a repeat request returns the
// existing pending claim; a denied claim is re-filed in place.
const submitClaim = async (res, claimRef, claimFields) => {
  const existing = await claimRef.get();
  if (existing.exists && existing.data().status === 'pending') {
    return res.json({
      success: true,
      data: { claim: { claimId: existing.id, ...existing.data() } }
    });
  }

  const claim = createVenueClaimRequest(claimFields);
  await claimRef.set(claim);
  await sendClaimAdminEmail(claim, claimRef.id);

  // Alert the admin in-app + push too — email alone is easy to miss.
  try {
    const notificationService = require('../services/notificationService');
    await notificationService.notifyStoreClaimSubmitted(claim, claimRef.id);
  } catch (notifyError) {
    console.error('⚠️ Claim admin notification failed:', notifyError.message);
  }

  res.status(existing.exists ? 200 : 201).json({
    success: true,
    data: { claim: { claimId: claimRef.id, ...claim } }
  });
};

// @desc    Ask to become the owner of an unclaimed sticker venue.
// @route   POST /api/rewards/venues/:venueId/claim
//          body: { contactName?, contactEmail?, contactPhone?, message? }
// @access  Private
exports.claimVenue = async (req, res) => {
  try {
    const userId = req.user.uid;
    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.params.venueId).get();
    if (!venueDoc.exists || venueDoc.data().active === false) {
      return res.status(404).json({ success: false, error: 'Venue not found' });
    }
    const venue = { venueId: venueDoc.id, ...venueDoc.data() };
    if (venue.ownerUserId) {
      return res.status(409).json({ success: false, error: 'This business already has an owner' });
    }

    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`));

    await submitClaim(res, claimRef, {
      venueId: venue.venueId,
      venueName: venue.venueName,
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body?.contactName,
      contactEmail: req.body?.contactEmail,
      contactPhone: req.body?.contactPhone,
      globalPlaceId: venue.globalPlaceId,
      googlePlaceId: venue.googlePlaceId,
      placeName: venue.placeName,
      placeAddress: venue.placeAddress
    });
  } catch (error) {
    console.error('❌ claimVenue failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    Claim a business straight from its place page, whether or not it
//          is enrolled in the sticker program. With an enrolled venue this
//          behaves like claimVenue; otherwise the claim records the place
//          and the admin enrolls + assigns after verifying.
// @route   POST /api/rewards/places/:placeId/claim
//          body: { googlePlaceId?, contactName?, contactEmail?, contactPhone?, message? }
// @access  Private
exports.claimPlace = async (req, res) => {
  try {
    const userId = req.user.uid;
    const placeId = req.params.placeId;

    // Enrolled venue? Same path as claimVenue.
    const venue = await rewardService.findVenueByPlace(placeId, req.body?.googlePlaceId);
    if (venue) {
      if (venue.ownerUserId) {
        return res.status(409).json({ success: false, error: 'This business already has an owner' });
      }
      const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
        .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`));
      return await submitClaim(res, claimRef, {
        venueId: venue.venueId,
        venueName: venue.venueName,
        userId,
        userEmail: req.user.email,
        userDisplayName: req.user.displayName || req.user.name,
        message: req.body?.message,
        contactName: req.body?.contactName,
        contactEmail: req.body?.contactEmail,
        contactPhone: req.body?.contactPhone,
        globalPlaceId: venue.globalPlaceId,
        googlePlaceId: venue.googlePlaceId,
        placeName: venue.placeName,
        placeAddress: venue.placeAddress
      });
    }

    // No venue: resolve the place itself (save doc id or global id)
    let placeName = null;
    let placeAddress = null;
    let globalPlaceId = null;
    let googlePlaceId = req.body?.googlePlaceId || null;
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (placeDoc.exists) {
      const place = placeDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = place.globalPlaceId || null;
      googlePlaceId = place.googlePlaceId || googlePlaceId;
    } else {
      const globalDoc = await db.collection('globalPlaces').doc(placeId).get();
      if (!globalDoc.exists) {
        return res.status(404).json({ success: false, error: 'Place not found' });
      }
      const place = globalDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = globalDoc.id;
      googlePlaceId = place.googlePlaceId || googlePlaceId;
    }

    // Any resolved place is claimable — ownership is verified by a human, so
    // Apple-sourced saves without a googlePlaceId are fine. (The place-exists
    // check above already 404'd unresolvable ids.)
    const placeKey = globalPlaceId || googlePlaceId || placeId;
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(sanitizeKeyPart(`place_${placeKey}_${userId}`));

    await submitClaim(res, claimRef, {
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body?.contactName,
      contactEmail: req.body?.contactEmail,
      contactPhone: req.body?.contactPhone,
      placeId,
      globalPlaceId,
      googlePlaceId,
      placeName,
      placeAddress
    });
  } catch (error) {
    console.error('❌ claimPlace failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    Add-and-claim: a store owner whose business was never saved by any
//          user submits it by details. Reuses an existing canonical venue
//          record when one matches (name + proximity), otherwise creates one —
//          no personal circle save required — then files the ownership claim.
// @route   POST /api/rewards/businesses/claim
//          body: { name, address, lat, lng, category?, phone?, website?,
//                  applePoiCategory?, contactName, contactEmail,
//                  contactPhone?, message? }
// @access  Private
exports.claimBusinessByDetails = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { name, address, lat, lng } = req.body || {};

    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, error: 'Business name is required' });
    }
    if (!address || !String(address).trim()) {
      return res.status(400).json({ success: false, error: 'Business address is required' });
    }
    if (typeof lat !== 'number' || typeof lng !== 'number' ||
        Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return res.status(400).json({ success: false, error: 'A map location is required' });
    }
    if (!req.body?.contactName || !req.body?.contactEmail) {
      return res.status(400).json({ success: false, error: 'Contact name and business email are required' });
    }

    const location = { type: 'Point', coordinates: [lng, lat] };
    const {
      findCanonicalByNameAndLocation,
      createGlobalPlaceFromDetails
    } = require('../services/globalPlaceResolver');

    // Reuse the canonical venue if it exists under any name/address variant
    let globalPlaceId;
    let placeName = String(name).trim();
    let placeAddress = String(address).trim();
    const matched = await findCanonicalByNameAndLocation(placeName, location);
    if (matched) {
      globalPlaceId = matched.id;
      placeName = matched.data().name || placeName;
      placeAddress = matched.data().address || placeAddress;
    } else {
      const created = await createGlobalPlaceFromDetails({
        name: placeName,
        address: placeAddress,
        location,
        category: req.body.category || 'other',
        phone: req.body.phone || null,
        website: req.body.website || null,
        applePoiCategory: req.body.applePoiCategory || null
      });
      globalPlaceId = created.resolvedId;
    }

    // Already an enrolled venue? Same guard as claimPlace.
    const venue = await rewardService.findVenueByPlace(globalPlaceId, req.body?.googlePlaceId);
    if (venue && venue.ownerUserId) {
      return res.status(409).json({ success: false, error: 'This business already has an owner' });
    }

    const claimRef = venue
      ? db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`))
      : db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .doc(sanitizeKeyPart(`place_${globalPlaceId}_${userId}`));

    await submitClaim(res, claimRef, {
      ...(venue ? { venueId: venue.venueId, venueName: venue.venueName } : {}),
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body.contactName,
      contactEmail: req.body.contactEmail,
      contactPhone: req.body?.contactPhone,
      globalPlaceId,
      googlePlaceId: req.body?.googlePlaceId || null,
      placeName,
      placeAddress
    });
  } catch (error) {
    console.error('❌ claimBusinessByDetails failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    List ownership claims for review
// @route   GET /api/rewards/claims?status=pending
// @access  Super user
exports.listClaims = async (req, res) => {
  try {
    const status = req.query.status || 'pending';
    // Single equality filter (automatic index); newest first in memory
    const snapshot = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .where('status', '==', status)
      .limit(100)
      .get();
    const claims = snapshot.docs
      .map((doc) => ({ claimId: doc.id, ...doc.data() }))
      .sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));

    res.json({ success: true, data: { claims, count: claims.length } });
  } catch (error) {
    console.error('❌ listClaims failed:', error);
    res.status(500).json({ success: false, error: 'Failed to load claims' });
  }
};

// @desc    Approve a claim: the claimant becomes the venue's owner and any
//          competing pending claims are denied.
// @route   POST /api/rewards/claims/:claimId/approve
// @access  Super user
exports.approveClaim = async (req, res) => {
  try {
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(req.params.claimId);
    const claimDoc = await claimRef.get();
    if (!claimDoc.exists) {
      return res.status(404).json({ success: false, error: 'Claim not found' });
    }
    const claim = claimDoc.data();
    if (claim.status !== 'pending') {
      return res.status(409).json({ success: false, error: `Claim is already ${claim.status}` });
    }

    // Claims on businesses not yet in the sticker program: approving
    // auto-enrolls the venue from the claim's place data, assigns the
    // claimant as owner, and emails the QR codes to the approving admin.
    if (!claim.venueId) {
      // Resolve location/category from the canonical place (or legacy save)
      let location = null;
      let category = null;
      let placeFound = false;
      if (claim.globalPlaceId) {
        const globalDoc = await db.collection('globalPlaces').doc(claim.globalPlaceId).get();
        if (globalDoc.exists) {
          placeFound = true;
          const coords = globalDoc.data().location?.coordinates; // GeoJSON [lng, lat]
          if (Array.isArray(coords) && coords.length === 2) {
            location = { lat: coords[1], lng: coords[0] };
          }
          category = globalDoc.data().category || null;
        }
      }
      if (!placeFound && claim.placeId) {
        const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(claim.placeId).get();
        if (placeDoc.exists) {
          placeFound = true;
          const coords = placeDoc.data().location?.coordinates;
          if (Array.isArray(coords) && coords.length === 2) {
            location = { lat: coords[1], lng: coords[0] };
          }
          category = placeDoc.data().category || null;
        }
      }
      if (!placeFound) {
        return res.status(404).json({ success: false, error: 'The claimed place no longer exists' });
      }

      const ownerEmail = claim.contactEmail || claim.userEmail || null;
      const venue = await rewardService.createVenue({
        venueName: claim.placeName || claim.venueName,
        placeName: claim.placeName || claim.venueName,
        placeAddress: claim.placeAddress || null,
        googlePlaceId: claim.googlePlaceId || null,
        globalPlaceId: claim.globalPlaceId || null,
        location,
        category: category || 'restaurant',
        contactName: claim.contactName || claim.userDisplayName || null,
        contactEmail: ownerEmail
      });

      // The claimant becomes the owner regardless of which email they gave
      // as business contact (it may differ from their account email)
      await rewardService.assignVenueOwner(venue.venueId, {
        ownerUserId: claim.userId,
        ownerEmail
      });

      // QR codes go to the approving admin for printing — best-effort
      let emailSent = false;
      if (req.user.email) {
        try {
          const { windowQR, registerQR } = await rewardService.generateQRBuffers(venue);
          await emailService.sendStickerQREmail(req.user.email, venue, windowQR, registerQR);
          emailSent = true;
        } catch (emailError) {
          console.error('⚠️ QR email failed (venue still enrolled):', emailError.message);
        }
      }

      const now = new Date().toISOString();
      await claimRef.update({
        status: 'approved',
        venueId: venue.venueId,
        resolvedBy: req.user.uid,
        resolvedAt: now,
        updatedAt: now
      });

      // Tell the new owner (in-app + push) — approval otherwise happens silently.
      try {
        const notificationService = require('../services/notificationService');
        await notificationService.notifyStoreClaimApproved(claim, claimRef.id, venue.venueId);
      } catch (notifyError) {
        console.error('⚠️ Claim-approved notification failed:', notifyError.message);
      }

      // And by email — the durable record, plus the Business-tier walkthrough
      if (ownerEmail) {
        emailService.sendClaimApprovedEmail(
          ownerEmail,
          claim.contactName || claim.userDisplayName || null,
          claim.placeName || claim.venueName || null
        ).catch((e) => console.error('⚠️ Claim-approved email failed:', e.message));
      }

      // Best-effort: close out competing pending claims for the same place
      try {
        const placeKey = claim.globalPlaceId || claim.googlePlaceId;
        if (placeKey) {
          const field = claim.globalPlaceId ? 'globalPlaceId' : 'googlePlaceId';
          const others = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
            .where(field, '==', placeKey)
            .get();
          await Promise.all(others.docs
            .filter((doc) => doc.id !== claimRef.id && doc.data().status === 'pending')
            .map((doc) => doc.ref.update({
              status: 'denied',
              resolvedBy: req.user.uid,
              resolvedAt: now,
              updatedAt: now,
              denialReason: 'Another claim was approved'
            })));
        }
      } catch (cleanupError) {
        console.error('⚠️ Failed to close competing claims:', cleanupError.message);
      }

      return res.json({
        success: true,
        data: {
          claim: { claimId: claimRef.id, ...claim, status: 'approved', venueId: venue.venueId, resolvedBy: req.user.uid, resolvedAt: now },
          venueId: venue.venueId,
          ownerEmail,
          enrolled: true,
          emailSent
        }
      });
    }

    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(claim.venueId).get();
    if (!venueDoc.exists) {
      return res.status(404).json({ success: false, error: 'Venue no longer exists' });
    }
    const now = new Date().toISOString();

    // The venue may have been assigned an owner (or another claim approved)
    // since this claim was filed — deny rather than silently reassign.
    if (venueDoc.data().ownerUserId) {
      await claimRef.update({
        status: 'denied',
        resolvedBy: req.user.uid,
        resolvedAt: now,
        updatedAt: now,
        denialReason: 'Venue already has an owner'
      });
      return res.status(409).json({ success: false, error: 'Venue already has an owner — claim denied' });
    }

    await rewardService.assignVenueOwner(claim.venueId, {
      ownerUserId: claim.userId,
      ownerEmail: claim.userEmail || venueDoc.data().ownerEmail
    });
    await claimRef.update({ status: 'approved', resolvedBy: req.user.uid, resolvedAt: now, updatedAt: now });

    // Tell the new owner (in-app + push) — approval otherwise happens silently.
    try {
      const notificationService = require('../services/notificationService');
      await notificationService.notifyStoreClaimApproved(claim, claimRef.id, claim.venueId);
    } catch (notifyError) {
      console.error('⚠️ Claim-approved notification failed:', notifyError.message);
    }

    // And by email — the durable record, plus the Business-tier walkthrough
    const approvedEmail = claim.contactEmail || claim.userEmail;
    if (approvedEmail) {
      emailService.sendClaimApprovedEmail(
        approvedEmail,
        claim.contactName || claim.userDisplayName || null,
        claim.venueName || claim.placeName || null
      ).catch((e) => console.error('⚠️ Claim-approved email failed:', e.message));
    }

    // Best-effort: close out competing pending claims for the same venue
    try {
      const others = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
        .where('venueId', '==', claim.venueId)
        .get();
      await Promise.all(others.docs
        .filter((doc) => doc.id !== claimRef.id && doc.data().status === 'pending')
        .map((doc) => doc.ref.update({
          status: 'denied',
          resolvedBy: req.user.uid,
          resolvedAt: now,
          updatedAt: now,
          denialReason: 'Another claim was approved'
        })));
    } catch (cleanupError) {
      console.error('⚠️ Failed to close competing claims:', cleanupError.message);
    }

    res.json({
      success: true,
      data: {
        claim: { claimId: claimRef.id, ...claim, status: 'approved', resolvedBy: req.user.uid, resolvedAt: now },
        venueId: claim.venueId,
        ownerEmail: claim.userEmail || null
      }
    });
  } catch (error) {
    console.error('❌ approveClaim failed:', error);
    res.status(500).json({ success: false, error: 'Failed to approve claim' });
  }
};

// @desc    Deny a claim, optionally with a reason shown to the claimant
// @route   POST /api/rewards/claims/:claimId/deny
// @access  Super user
exports.denyClaim = async (req, res) => {
  try {
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(req.params.claimId);
    const claimDoc = await claimRef.get();
    if (!claimDoc.exists) {
      return res.status(404).json({ success: false, error: 'Claim not found' });
    }
    if (claimDoc.data().status !== 'pending') {
      return res.status(409).json({ success: false, error: `Claim is already ${claimDoc.data().status}` });
    }

    const now = new Date().toISOString();
    const update = {
      status: 'denied',
      resolvedBy: req.user.uid,
      resolvedAt: now,
      updatedAt: now,
      denialReason: (req.body?.reason || '').trim() || null
    };
    await claimRef.update(update);

    res.json({ success: true, data: { claim: { claimId: claimRef.id, ...claimDoc.data(), ...update } } });
  } catch (error) {
    console.error('❌ denyClaim failed:', error);
    res.status(500).json({ success: false, error: 'Failed to deny claim' });
  }
};

// ---------- Admin (guarded by ADMIN_SECRET in the router) ----------

// @desc    Create a sticker venue; returns both codes + QR target URLs
// @route   POST /api/rewards/admin/venues
// @access  Admin
exports.createVenue = async (req, res) => {
  try {
    const errors = validateStickerVenue(req.body);
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: 'Validation error', errors });
    }

    const venue = await rewardService.createVenue(req.body);
    const baseUrl = process.env.STICKER_LINK_BASE_URL
      || 'https://api.favcircles.com';

    res.status(201).json({
      success: true,
      data: {
        venueId: venue.venueId,
        venueName: venue.venueName,
        windowCode: venue.windowCode,
        registerCode: venue.registerCode,
        windowStickerUrl: `${baseUrl}/s/${venue.windowCode}`,
        registerCardUrl: `${baseUrl}/s/${venue.registerCode}`,
        offers: venue.offers
      }
    });
  } catch (error) {
    console.error('❌ Venue creation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to create venue' });
  }
};

// @desc    List sticker venues with their stats
// @route   GET /api/rewards/admin/venues
// @access  Admin
exports.listVenues = async (req, res) => {
  try {
    const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .orderBy('createdAt', 'desc')
      .limit(200)
      .get();

    const venues = snapshot.docs.map((doc) => ({ venueId: doc.id, ...doc.data() }));
    res.json({ success: true, data: { venues, count: venues.length } });
  } catch (error) {
    console.error('❌ Venue listing failed:', error);
    res.status(500).json({ success: false, error: 'Failed to list venues' });
  }
};


// ============================================================
// Brand accounts (virtual stores) — account-anchored businesses
// ============================================================
// A "virtual" venue is a stickerVenues doc with isVirtual: true and no
// location/Google identity: it inherits offers, announcements, premium
// gating, the dashboard, and the register-QR loyalty scan, but can never
// surface on a map or in Nearby (those read globalPlaces, not stickerVenues).
// The user doc carries the brand's presentation (storefront{}).

const piggyBankService = require('../services/piggyBankService');

const STOREFRONT_URL_FIELDS = ['website', 'catalogUrl'];

const sanitizeStorefrontInput = (body) => {
  const errors = [];
  const out = {};

  if (body.enabled !== undefined) out.enabled = body.enabled === true;

  if (body.businessName !== undefined) {
    const name = String(body.businessName || '').trim();
    if (!name) errors.push('businessName must not be empty');
    if (name.length > 60) errors.push('businessName must be 60 characters or fewer');
    out.businessName = name;
  }

  if (body.about !== undefined) {
    const about = String(body.about || '').trim();
    if (about.length > 1000) errors.push('about must be 1000 characters or fewer');
    out.about = about || null;
  }

  STOREFRONT_URL_FIELDS.forEach((field) => {
    if (body[field] === undefined) return;
    const raw = String(body[field] || '').trim();
    if (!raw) { out[field] = null; return; }
    if (raw.length > 300) errors.push(`${field} must be 300 characters or fewer`);
    out[field] = /^https?:\/\//i.test(raw) ? raw : `https://${raw}`;
  });

  if (body.contactEmail !== undefined) {
    const email = String(body.contactEmail || '').trim().toLowerCase();
    if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      errors.push('contactEmail must be a valid email address');
    }
    out.contactEmail = email || null;
  }

  if (body.findUsAtCircleId !== undefined) {
    out.findUsAtCircleId = body.findUsAtCircleId ? String(body.findUsAtCircleId) : null;
  }

  return { errors, out };
};

// @desc    Configure the caller's brand storefront (profile card content)
// @route   PUT /api/rewards/storefront
// @access  Business standing (active owner subscription, manual verify, or super user)
exports.updateStorefront = async (req, res) => {
  try {
    if (!isOwnerPremiumUser(req.user)) {
      return res.status(403).json({
        success: false,
        upgradeRequired: true,
        error: 'FavCircles Business is required to set up a storefront'
      });
    }

    const { errors, out } = sanitizeStorefrontInput(req.body);
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    // The "Find us at" circle must be one of the caller's own circles —
    // circles key ownership on `owner`
    if (out.findUsAtCircleId) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(out.findUsAtCircleId).get();
      const circleOwner = circleDoc.exists ? circleDoc.data().owner : null;
      if (!circleDoc.exists || String(circleOwner) !== String(req.user.uid)) {
        return res.status(400).json({ success: false, error: 'findUsAtCircleId must be one of your own circles' });
      }
    }

    const existing = (req.user.storefront && typeof req.user.storefront === 'object')
      ? req.user.storefront : {};
    const storefront = {
      enabled: existing.enabled === true,
      businessName: existing.businessName || null,
      about: existing.about || null,
      website: existing.website || null,
      catalogUrl: existing.catalogUrl || null,
      contactEmail: existing.contactEmail || null,
      findUsAtCircleId: existing.findUsAtCircleId || null,
      ...out,
      updatedAt: new Date().toISOString()
    };

    if (storefront.enabled && !storefront.businessName) {
      return res.status(400).json({ success: false, error: 'businessName is required to enable the storefront' });
    }

    await db.collection(COLLECTIONS.USERS).doc(req.user.uid).update({ storefront });
    res.json({ success: true, data: { storefront } });
  } catch (error) {
    console.error('❌ Storefront update failed:', error);
    res.status(500).json({ success: false, error: 'Failed to update storefront' });
  }
};

// @desc    Public storefront for a business account: presentation + the
//          account's live venues (offers/announcements) + Find-us-at circle
// @route   GET /api/rewards/storefront/:userId
// @access  Private (any signed-in user)
exports.getStorefront = async (req, res) => {
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(req.params.userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({ success: false, error: 'User not found' });
    }
    const owner = userDoc.data();
    const storefront = owner.storefront;
    if (!storefront || storefront.enabled !== true) {
      return res.json({ success: true, data: { storefront: null } });
    }

    // The account's venues (physical and virtual), with live offer content
    const venuesSnap = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .where('ownerUserId', '==', userDoc.id)
      .limit(20)
      .get();
    const venues = venuesSnap.docs
      .map((doc) => ({ venueId: doc.id, ...doc.data() }))
      .filter((venue) => venue.active !== false)
      .map((venue) => {
        const live = isCompActive(venue) || isOwnerPremiumForVenue(owner, venue.venueId, venue);
        return {
          ...publicVenueInfo(venue),
          loyaltyLive: live,
          offers: live
            ? activeOffers(venue).map(({ offerId, title, pointsCost }) => ({ offerId, title, pointsCost }))
            : [],
          announcements: live ? rewardService.activeAnnouncements(venue) : []
        };
      });

    // Find-us-at circle summary (conference schedule etc.)
    let findUsAtCircle = null;
    if (storefront.findUsAtCircleId) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(storefront.findUsAtCircleId).get();
      if (circleDoc.exists && !circleDoc.data().deletedAt) {
        const circle = circleDoc.data();
        findUsAtCircle = {
          id: circleDoc.id,
          name: circle.name,
          placesCount: circle.placesCount || (circle.places || []).length || 0
        };
      }
    }

    res.json({
      success: true,
      data: {
        storefront: {
          businessName: storefront.businessName,
          about: storefront.about || null,
          website: storefront.website || null,
          catalogUrl: storefront.catalogUrl || null,
          contactEmail: storefront.contactEmail || null
        },
        findUsAtCircle,
        venues,
        ownerDisplayName: owner.displayName || null
      }
    });
  } catch (error) {
    console.error('❌ Storefront read failed:', error);
    res.status(500).json({ success: false, error: 'Failed to load storefront' });
  }
};

// @desc    Self-service creation of the account's online store (virtual venue)
// @route   POST /api/rewards/venues/virtual
// @access  Business standing
exports.createVirtualVenue = async (req, res) => {
  try {
    if (!isOwnerPremiumUser(req.user)) {
      return res.status(403).json({
        success: false,
        upgradeRequired: true,
        error: 'FavCircles Business is required to create an online store'
      });
    }

    const venueName = String(req.body.venueName || '').trim();
    if (!venueName) {
      return res.status(400).json({ success: false, error: 'venueName is required' });
    }

    // One online store per account — a brand IS the account
    const existing = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .where('ownerUserId', '==', req.user.uid)
      .where('isVirtual', '==', true)
      .limit(1)
      .get();
    if (!existing.empty) {
      return res.status(400).json({
        success: false,
        error: 'This account already has an online store',
        venueId: existing.docs[0].id
      });
    }

    const venue = await rewardService.createVenue({
      venueName,
      isVirtual: true,
      category: req.body.category || 'retail',
      ownerUserId: req.user.uid,
      contactEmail: req.body.contactEmail || req.user.email || null,
      contactName: req.user.displayName || null
    });

    // Bind an unbound business subscription to this venue (same rule as
    // receipt verification: never silently move an existing binding)
    if (!req.user.ownerSubscriptionVenueId && req.user.ownerSubscriptionStatus) {
      await db.collection(COLLECTIONS.USERS).doc(req.user.uid)
        .update({ ownerSubscriptionVenueId: venue.venueId })
        .catch((error) => console.error('⚠️ Subscription binding failed:', error.message));
    }

    res.status(201).json({
      success: true,
      data: {
        venueId: venue.venueId,
        venueName: venue.venueName,
        isVirtual: true,
        windowCode: venue.windowCode,
        registerCode: venue.registerCode,
        windowStickerUrl: rewardService.stickerUrl(venue.windowCode),
        registerCardUrl: rewardService.stickerUrl(venue.registerCode)
      }
    });
  } catch (error) {
    console.error('❌ Virtual venue creation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to create online store' });
  }
};

// ---------- Redemption codes (order-box cards / booth handouts) ----------

const REDEMPTION_CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const REDEMPTION_CODE_LENGTH = 8;

const randomRedemptionCode = () => {
  let code = '';
  for (let i = 0; i < REDEMPTION_CODE_LENGTH; i++) {
    code += REDEMPTION_CODE_CHARS.charAt(Math.floor(Math.random() * REDEMPTION_CODE_CHARS.length));
  }
  return code;
};

// @desc    Create a batch of single-use loyalty codes for a venue
// @route   POST /api/rewards/venues/:venueId/codes
// @access  Venue owner + Business tier
exports.createRedemptionCodes = async (req, res) => {
  try {
    const errors = validateRedemptionCodeBatch(req.body);
    if (errors.length > 0) {
      return res.status(400).json({ success: false, error: errors.join('. ') });
    }

    const venue = req.venue;
    const batchId = `batch_${Date.now()}`;
    const codes = [];
    const codesRef = db.collection(STICKER_COLLECTIONS.REDEMPTION_CODES);

    for (let i = 0; i < req.body.count; i++) {
      // Doc ID IS the code; create() collisions regenerate
      let created = false;
      for (let attempt = 0; attempt < 5 && !created; attempt++) {
        const code = randomRedemptionCode();
        const doc = createRedemptionCode({
          venueId: venue.venueId,
          venueName: venue.venueName,
          points: req.body.points,
          label: req.body.label || null,
          batchId,
          expiresAt: req.body.expiresAt || null,
          createdBy: req.user.uid
        });
        try {
          await codesRef.doc(code).create(doc);
          codes.push(code);
          created = true;
        } catch (error) {
          if (!(error.code === 6 || /already exists/i.test(error.message || ''))) throw error;
        }
      }
      if (!created) {
        return res.status(500).json({ success: false, error: 'Code generation collided repeatedly; try again' });
      }
    }

    res.status(201).json({
      success: true,
      data: { batchId, points: req.body.points, label: req.body.label || null, expiresAt: req.body.expiresAt || null, codes }
    });
  } catch (error) {
    console.error('❌ Redemption code creation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to create codes' });
  }
};

// @desc    List a venue's redemption codes (owner management view)
// @route   GET /api/rewards/venues/:venueId/codes
// @access  Venue owner
exports.listRedemptionCodes = async (req, res) => {
  try {
    const snapshot = await db.collection(STICKER_COLLECTIONS.REDEMPTION_CODES)
      .where('venueId', '==', req.venue.venueId)
      .limit(1000)
      .get();
    const codes = snapshot.docs
      .map((doc) => {
        const data = doc.data();
        return {
          code: doc.id,
          points: data.points,
          label: data.label,
          batchId: data.batchId,
          active: data.active !== false,
          redeemedBy: data.redeemedBy || null,
          redeemedAt: data.redeemedAt || null,
          expiresAt: data.expiresAt || null,
          createdAt: data.createdAt
        };
      })
      .sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));

    const summary = {
      total: codes.length,
      redeemed: codes.filter((c) => !c.active).length
    };
    res.json({ success: true, data: { codes, summary } });
  } catch (error) {
    console.error('❌ Redemption code listing failed:', error);
    res.status(500).json({ success: false, error: 'Failed to list codes' });
  }
};

// @desc    Redeem a single-use code for venue loyalty points (+ FavCoins)
// @route   POST /api/rewards/redeem-code
// @access  Private
exports.redeemCode = async (req, res) => {
  try {
    const code = String(req.body.code || '').trim().toUpperCase();
    if (!code) {
      return res.status(400).json({ success: false, error: 'code is required' });
    }

    const codeRef = db.collection(STICKER_COLLECTIONS.REDEMPTION_CODES).doc(code);
    const codeDoc = await codeRef.get();
    if (!codeDoc.exists) {
      return res.status(404).json({ success: false, error: 'Code not found' });
    }
    const codeData = codeDoc.data();
    if (codeData.active === false) {
      return res.status(400).json({ success: false, error: 'This code has already been redeemed' });
    }
    if (codeData.expiresAt && new Date(codeData.expiresAt) <= new Date()) {
      return res.status(400).json({ success: false, error: 'This code has expired' });
    }

    // Loyalty must be live at the issuing venue (same pause rule as scans)
    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(codeData.venueId).get();
    if (!venueDoc.exists) {
      return res.status(400).json({ success: false, error: 'This code is no longer valid' });
    }
    const venue = { venueId: venueDoc.id, ...venueDoc.data() };
    let live = isCompActive(venue);
    if (!live && venue.ownerUserId) {
      const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(venue.ownerUserId).get();
      live = ownerDoc.exists && isOwnerPremiumForVenue(ownerDoc.data(), venue.venueId, venue);
    }
    if (!live) {
      console.warn(`[loyalty-integrity] code redemption paused venue=${venue.venueId} code=${code}`);
      return res.status(400).json({ success: false, error: 'Loyalty is paused at this business' });
    }

    // Claim the code transactionally — first writer wins
    const userId = req.user.uid;
    try {
      await db.runTransaction(async (tx) => {
        const fresh = await tx.get(codeRef);
        if (!fresh.exists || fresh.data().active === false) {
          throw new Error('CODE_TAKEN');
        }
        tx.update(codeRef, {
          active: false,
          redeemedBy: userId,
          redeemedAt: new Date().toISOString()
        });
      });
    } catch (error) {
      if (error.message === 'CODE_TAKEN') {
        return res.status(400).json({ success: false, error: 'This code has already been redeemed' });
      }
      throw error;
    }

    const award = await rewardService.awardPoints({
      userId,
      type: 'code_redemption',
      points: codeData.points,
      venueId: venue.venueId,
      venueName: venue.venueName,
      code,
      idempotencyKey: `code:${code}`
    });

    rewardService.incrementVenueStats(venue.venueId, 'codeRedemptions').catch(() => {});
    piggyBankService.credit({
      userId,
      eventType: 'brand_code_redeemed',
      sourceRef: { code, venueId: venue.venueId }
    }).catch(() => {});

    const balance = await rewardService.getBalance(userId);
    res.json({
      success: true,
      data: {
        awarded: award.duplicate ? null : { points: codeData.points, venueName: venue.venueName },
        duplicate: award.duplicate === true,
        balance
      }
    });
  } catch (error) {
    console.error('❌ Code redemption failed:', error);
    res.status(500).json({ success: false, error: 'Failed to redeem code' });
  }
};
