// controllers/venues/storefrontController.js
// Brand accounts: storefront card and virtual venues
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const { isOwnerPremiumUser, isOwnerPremiumForVenue, isCompActive } = require('../../services/ownerSubscriptionService');
const db = getFirestore();
const STOREFRONT_URL_FIELDS = ['website', 'catalogUrl'];
const { venueManagerIds, publicVenueInfo, activeOffers } = require('../../services/venueHelpers.js');

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
  ownerUserId: venue.ownerUserId || null,
  managerUserIds: venueManagerIds(venue),
        registerCardUrl: rewardService.stickerUrl(venue.registerCode)
      }
    });
  } catch (error) {
    console.error('❌ Virtual venue creation failed:', error);
    res.status(500).json({ success: false, error: 'Failed to create online store' });
  }
};
