// controllers/venues/venueAdminController.js
// Superuser/admin: create/list venues, set owner, superusers, email QR
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { validateStickerVenue, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const emailService = require('../../services/emailService');
const db = getFirestore();
const { venueManagerIds, venueGlobalPlaceId, ownerVenueInfo } = require('../../services/venueHelpers.js');
const { venueLoyaltyStatus } = require('../../services/ownerSubscriptionService');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');
const { serializeDates } = require('../../utils/wireDates');

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
  ownerUserId: venue.ownerUserId || null,
  managerUserIds: venueManagerIds(venue),
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

// Lightweight account row for the admin store page
const accountRow = async (userId) => {
  try {
    const doc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const u = doc.exists ? doc.data() : {};
    return {
      userId,
      displayName: u.displayName || u.name || null,
      email: u.email || null,
      username: u.username || null,
      subscriptionStatus: u.ownerSubscriptionStatus || null,
      subscriptionExpiresAt: u.ownerSubscriptionExpiryDate || null,
      subscriptionVenueId: u.ownerSubscriptionVenueId || null,
      manuallyVerified: u.ownerManuallyVerified === true,
      // Super-users pass every Business gate, so their stores read as live
      isSuperUser: u.isSuperUser === true
    };
  } catch (error) {
    return { userId, displayName: null, email: null, username: null };
  }
};

// @desc    Everything a super-user needs about one store on one page:
//          identity, both QR codes, loyalty status and why, owner + team,
//          pending claims, all counters and this month's, storefront size.
// @route   GET /api/rewards/venues/:venueId/admin
// @access  Super user (requireVenueOwner loads req.venue)
exports.getVenueAdminDetail = async (req, res) => {
  try {
    const venue = req.venue;
    const globalPlaceId = await venueGlobalPlaceId(venue);
    const monthKey = rewardService.currentMonthKey();

    const [loyalty, owner, managers, claimsSnap, globalDoc, saveDocs] = await Promise.all([
      venueLoyaltyStatus(venue),
      venue.ownerUserId ? accountRow(venue.ownerUserId) : null,
      Promise.all(venueManagerIds(venue).map(accountRow)),
      db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
        .where('venueId', '==', venue.venueId).get(),
      globalPlaceId
        ? db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).get()
        : null,
      // Everyone who saved the place (any route in), distinct by saver
      globalPlaceId
        ? db.collection(COLLECTIONS.PLACES)
          .where('globalPlaceId', '==', globalPlaceId)
          .where('deletedAt', '==', null)
          .select('addedBy')
          .get()
          .then((snap) => snap.docs.map((d) => d.data()))
        : []
    ]);

    const pendingClaims = claimsSnap.docs
      .map((doc) => ({ claimId: doc.id, ...doc.data() }))
      .filter((c) => c.status === 'pending')
      .map((c) => ({
        claimId: c.claimId,
        name: c.contactName || c.userDisplayName || null,
        email: c.contactEmail || c.userEmail || null,
        phone: c.contactPhone || null,
        message: c.message || null,
        createdAt: c.createdAt || null
      }));

    const stats = venue.stats || {};
    const month = (venue.statsMonthly || {})[monthKey] || {};
    const storefront = venue.storefront || {};
    const count = (v) => (Array.isArray(v) ? v.length : 0);

    const data = {
      venue: {
        ...ownerVenueInfo(venue),
        registerCardUrl: rewardService.stickerUrl(venue.registerCode),
        active: venue.active !== false,
        updatedAt: venue.updatedAt || null
      },
      loyalty: {
        active: loyalty.active,
        reason: loyalty.reason,
        comped: venue.loyaltyComped === true,
        compedUntil: venue.loyaltyCompedUntil || null,
        compReason: venue.loyaltyCompReason || null
      },
      owner,
      managers,
      pendingClaims,
      stats: {
        scans: stats.scans || 0,
        signups: stats.signups || 0,
        stickerSaves: stats.saves || 0,
        savers: new Set(saveDocs.map((d) => d.addedBy).filter(Boolean)).size,
        followers: (globalDoc && globalDoc.exists && globalDoc.data().followersCount) || 0,
        visits: stats.visits || 0,
        redemptions: stats.redemptions || 0,
        codeRedemptions: stats.codeRedemptions || 0,
        clipScans: stats.clipScans || 0,
        clipSignups: stats.clipSignups || 0,
        clipInstalls: stats.clipInstalls || 0
      },
      thisMonth: {
        scans: month.scans || 0,
        signups: month.signups || 0,
        stickerSaves: month.saves || 0,
        visits: month.visits || 0,
        redemptions: month.redemptions || 0
      },
      storefront: {
        actions: count(storefront.actions),
        offerings: count(storefront.offerings),
        gallery: count(storefront.gallery)
      }
    };

    res.json({ success: true, data: serializeDates(data) });
  } catch (error) {
    console.error('❌ Venue admin detail failed:', error);
    res.status(500).json({ success: false, error: 'Failed to load store' });
  }
};
