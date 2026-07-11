// backend/controllers/rewardController.js
// Sticker rewards endpoints: scan, save confirmation, balance, offer redemption,
// and admin venue management.

const { getFirestore } = require('../config/firebase');
const geofire = require('geofire-common');
const { COLLECTIONS } = require('../models/FirestoreModels');
const {
  validateStickerVenue,
  validateOfferInput,
  validateEarnRate,
  STICKER_COLLECTIONS
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

    await venueDoc.ref.update({
      ownerUserId,
      ownerEmail: normalizedEmail,
      updatedAt: new Date().toISOString()
    });

    res.json({
      success: true,
      data: { venueId: venueDoc.id, ownerEmail: normalizedEmail }
    });
  } catch (error) {
    console.error('❌ setVenueOwner failed:', error);
    res.status(500).json({ success: false, error: 'Failed to assign venue owner' });
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
