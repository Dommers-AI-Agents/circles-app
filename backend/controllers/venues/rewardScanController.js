// controllers/venues/rewardScanController.js
// Consumer side: sticker scan, sticker-save confirm, balance, offers, redeem, venue-by-place, /me
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const geofire = require('geofire-common');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { sanitizeKeyPart, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const rewardConfig = require('../../config/rewardConfig');
const { isOwnerPremiumUser, isOwnerPremiumForVenue, isVenueLoyaltyActive, isCompActive, venueLoyaltyStatus } = require('../../services/ownerSubscriptionService');
const db = getFirestore();
const { isVenueTeamMember, publicVenueInfo, activeOffers } = require('../../services/venueHelpers.js');

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
      // Generic "Join FavCircles" code: no venue to reward — never award the
      // signup bonus against the virtual doc (that stays reserved for the
      // first REAL partner store the user scans).
      const signupResult = venue.genericJoin
        ? { awarded: false, reason: 'generic_join' }
        : await rewardService.awardStickerSignup(userId, venue);
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

    const isOwner = isVenueTeamMember(venue, userId)
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

    // Managers see the same owner UI as the billing owner
    if (!ownsVenues) {
      const managedHit = await venuesRef
        .where('managerUserIds', 'array-contains', req.user.uid).limit(1).get();
      ownsVenues = !managedHit.empty;
    }

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
