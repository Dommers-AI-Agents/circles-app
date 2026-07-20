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
  sanitizeKeyPart,
  STICKER_COLLECTIONS,
  MAX_ANNOUNCEMENTS
} = require('../models/StickerModels');
const rewardService = require('../services/rewardService');
const rewardConfig = require('../config/rewardConfig');
const emailService = require('../services/emailService');

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
  location: venue.location || null
});

const activeOffers = (venue) => (venue.offers || []).filter((o) => o.active !== false);

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
      const { rewardPoints } = await rewardService.getBalance(userId);

      return res.json({
        success: true,
        data: {
          kind: 'window',
          venue: publicVenueInfo(venue),
          awarded: signupResult.awarded
            ? { type: 'sticker_signup', points: signupResult.points }
            : null,
          alreadySaved,
          balance: rewardPoints
        }
      });
    }

    // Register card: purchase proof (possession of the physical card is the
    // gate — points come from the venue's owner-configured earn rate)
    const visitResult = await rewardService.awardVenueVisit(userId, venue);

    const { rewardPoints } = await rewardService.getBalance(userId);
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
    const { rewardPoints } = await rewardService.getBalance(userId);

    res.json({
      success: true,
      data: {
        awarded: result.awarded ? { type: 'sticker_save', points: result.points } : null,
        alreadyAwarded: !!result.duplicate,
        balance: rewardPoints
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
    const { rewardPoints, events } = await rewardService.getBalance(req.user.uid);
    res.json({ success: true, data: { balance: rewardPoints, events } });
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

    const result = await rewardService.redeemOffer(req.user.uid, venueId, offerId);
    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error });
    }

    const { rewardPoints } = await rewardService.getBalance(req.user.uid);
    res.json({ success: true, data: { voucher: result.voucher, balance: rewardPoints } });
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

    const withOffers = snapshot.docs
      .map((doc) => ({ venueId: doc.id, ...doc.data() }))
      .filter((venue) => activeOffers(venue).length > 0);

    const savedPlaceIds = await rewardService.getSavedVenuePlaceIds(
      userId,
      withOffers.map((venue) => venue.googlePlaceId)
    );

    const venues = withOffers.map((venue) => ({
      ...publicVenueInfo(venue),
      earnRate: rewardService.effectiveEarnRate(venue),
      savedByUser: !!(venue.googlePlaceId && savedPlaceIds.has(venue.googlePlaceId)),
      distanceMeters: hasCoords && venue.location
        ? geofire.distanceBetween([lat, lng], [venue.location.lat, venue.location.lng]) * 1000
        : null,
      offers: activeOffers(venue).map(({ offerId, title, pointsCost }) => ({
        offerId, title, pointsCost
      }))
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
    // render from this one request (skip getBalance — no need for the history)
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const balance = (userDoc.exists && userDoc.data().rewardPoints) || 0;

    res.json({
      success: true,
      data: { venues: venues.slice(0, rewardConfig.NEARBY_MAX_VENUES), balance }
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
      // Not in the sticker program — but a Google-backed business can still
      // be claimed by its owner ("Is this your store?"), so surface the
      // caller's claim state keyed by the place.
      let googlePlaceId = req.query.googlePlaceId || null;
      let globalPlaceId = null;
      try {
        const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(req.params.placeId).get();
        if (placeDoc.exists) {
          googlePlaceId = placeDoc.data().googlePlaceId || googlePlaceId;
          globalPlaceId = placeDoc.data().globalPlaceId || null;
        } else {
          const globalDoc = await db.collection('globalPlaces').doc(req.params.placeId).get();
          if (globalDoc.exists) {
            googlePlaceId = globalDoc.data().googlePlaceId || googlePlaceId;
            globalPlaceId = globalDoc.id;
          }
        }
      } catch (lookupError) {
        console.error('⚠️ Claimability lookup failed:', lookupError.message);
      }

      const claim = { canClaim: !!googlePlaceId, myClaimStatus: null };
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
    const balance = (userDoc.exists && userDoc.data().rewardPoints) || 0;

    res.json({
      success: true,
      data: {
        venue: {
          ...publicVenueInfo(venue),
          earnRate: rewardService.effectiveEarnRate(venue)
        },
        offers: activeOffers(venue).map(({ offerId, title, pointsCost }) => ({
          offerId, title, pointsCost
        })),
        announcements: rewardService.activeAnnouncements(venue),
        balance,
        isOwner,
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
  googlePlaceId: venue.googlePlaceId,
  globalPlaceId: venue.globalPlaceId,
  location: venue.location || null,
  windowCode: venue.windowCode,
  registerCode: venue.registerCode,
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

    res.json({
      success: true,
      data: { venues: venues.map(ownerVenueInfo), count: venues.length }
    });
  } catch (error) {
    console.error('❌ Failed to load owned venues:', error);
    res.status(500).json({ success: false, error: 'Failed to load your venues' });
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
    res.json({ success: true, data: { announcements } });
  } catch (error) {
    console.error('❌ Failed to delete announcement:', error);
    res.status(500).json({ success: false, error: 'Failed to delete announcement' });
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

    // Only real businesses (Google-backed) can be claimed
    if (!googlePlaceId) {
      return res.status(400).json({ success: false, error: 'This place cannot be claimed' });
    }

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
      || 'https://circles-backend-196924649787.us-central1.run.app';

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
