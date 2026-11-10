// controllers/venues/rewardScanController.js
// Consumer side: sticker scan, sticker-save confirm, balance, offers, redeem, venue-by-place, /me
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const geofire = require('geofire-common');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { sanitizeKeyPart, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const { sendServiceError } = require('../../utils/serviceError');
const { scanLocationCheck } = require('../../services/scanLocation');
const { recordScanAttempt } = require('../../services/scanAttempts');
const rewardProgress = require('../../services/rewardProgress');
const nearbyEventsService = require('../../services/nearbyEventsService');
const { listLiveVenues } = require('../../services/liveVenues');
const rewardConfig = require('../../config/rewardConfig');
const { isOwnerPremiumUser, isOwnerPremiumForVenue, isVenueLoyaltyActive, registerScanEarns, loyaltyNeverStarted, isVenueBusinessLive } = require('../../services/ownerSubscriptionService');
const db = getFirestore();
const { isVenueTeamMember, isBrowsableBy, publicVenueInfo, activeOffers } = require('../../services/venueHelpers.js');
const { findOwnSaveOfStore } = require('../../services/ownSaveOfVenue');
const { saveStoreForClip } = require('../../services/clipStoreSave');
// The store welcome email goes out after the first scan at the store they
// joined at (once; fire-and-forget, never slows the scan)
const welcomeAfterScan = (userId, venue, awardedPoints, balance) => {
  require('../../services/storeWelcomeEmailService')
    .maybeSendAfterScan(userId, venue, { awardedPoints, balance }).catch(() => {});
};

// Did this user already save the store's place? One rule, shared with Add
// Place's duplicate check (services/ownSaveOfVenue), so a scan never offers a
// save that the save would then refuse.
const userHasSavedVenuePlace = async (userId, venue) => !!(await findOwnSaveOfStore({ userId, venue }));

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
// @route GET /api/rewards/code-name/:code
// The store a code belongs to, for the app's "Checking rewards at <store>…"
// bubble while the scan itself runs. One indexed lookup, cached briefly.
const codeNameCache = new Map();
exports.codeName = async (req, res) => {
  try {
    const code = String(req.params.code || '').trim().toUpperCase();
    const hit = codeNameCache.get(code);
    if (hit && hit.at > Date.now() - 10 * 60 * 1000) return res.json({ success: true, data: { venueName: hit.name } });
    const venue = await rewardService.findVenueByCode(code);
    if (!venue || venue.active === false) return res.status(404).json({ success: false, error: 'Unknown code' });
    const name = venue.genericJoin ? null : (venue.venueName || venue.placeName || null);
    if (codeNameCache.size > 2000) codeNameCache.clear();
    codeNameCache.set(code, { name, at: Date.now() });
    res.json({ success: true, data: { venueName: name } });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Lookup failed' });
  }
};

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

    // The generic "Join FavCircles" code (JOINUS): not a store. The virtual
    // "FavCircles" venue behind it is a demo record, never something to save
    // (Wes, 2026-11-09: "the FavCircles virtual store is just a demo"). The
    // app takes the person into using FavCircles — the first-run favorite
    // spot — instead of a store page.
    if (venue.genericJoin) {
      rewardService.incrementVenueStats(venue.venueId, 'scans');
      const { rewardPoints } = await rewardService.getBalance(userId, { withEvents: false });
      return res.json({
        success: true,
        data: {
          kind: 'generic',
          generic: true,
          venue: publicVenueInfo(venue),
          awarded: null,
          saved: false,
          alreadySaved: false,
          savedPlace: null,
          balance: rewardPoints,
          venueBalance: 0,
          loyaltyLive: false,
          offers: []
        }
      });
    }

    if (venue.kind === 'window') {
      rewardService.incrementVenueStats(venue.venueId, 'scans');
      // The App Clip saves the store as it signs them in: they already said
      // yes on "Love it here? Save us." (Wes, 2026-11-01). Only the clip asks
      // (`save: true`); an in-app window scan keeps its circle picker.
      const clipSave = req.body.save === true;
      const savedDoc = await findOwnSaveOfStore({ userId, venue });
      let alreadySaved = !!savedDoc;
      // Which circle it's saved in, for the app's "Show me" (2026-10-30)
      let savedPlace = savedDoc ? { placeId: savedDoc.id, circleId: savedDoc.data().circleId || null } : null;
      let saved = false;
      let savePending = false;
      if (clipSave && !alreadySaved) {
        const outcome = await saveStoreForClip(req.user, venue);
        saved = outcome.saved;
        alreadySaved = outcome.alreadySaved;
        savedPlace = outcome.savedPlace || savedPlace;
        savePending = outcome.pending === true;
      }
      // Saving the store pays its save bonus once, only where the store's
      // rewards are live (Wes, 2026-11-01, superseding 2026-10-30's "the
      // window QR never pays"). Not live: saved, nothing said about points.
      const loyaltyLive = await isVenueLoyaltyActive(venue);
      // Bring a friend (2026-11-09): the link carried ?ref=<inviter>; remember
      // who, so the friend's first purchase pays them both
      if (req.body.ref) {
        require('../../services/storeReferrals').remember({ venue, refUserId: String(req.body.ref), newUserId: userId, live: loyaltyLive })
          .catch((e) => console.error('referral remember failed', e.message));
      }
      let awarded = null;
      if (clipSave && loyaltyLive && (saved || alreadySaved)) {
        const result = await rewardService.awardStickerSave(userId, venue);
        if (result.awarded) awarded = { type: 'sticker_save', points: result.points };
      }
      const { rewardPoints, venueBalances } = await rewardService.getBalance(userId, { withEvents: false });
      const venueBalance = (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0;
      const offers = loyaltyLive ? activeOffers(venue) : [];
      const earnRate = loyaltyLive ? rewardService.effectiveEarnRate(venue) : null;
      const next = loyaltyLive ? rewardProgress.nextReward(offers, venueBalance, earnRate) : null;
      welcomeAfterScan(userId, venue, awarded ? awarded.points : 0, venueBalance);
      return res.json({
        success: true,
        data: {
          kind: 'window',
          venue: publicVenueInfo(venue),
          awarded,
          saved,
          ...(savePending ? { savePending: true } : {}),
          alreadySaved,
          savedPlace,
          balance: rewardPoints,
          venueBalance,
          loyaltyLive,
          saveBonusPoints: loyaltyLive ? rewardService.effectiveSavePoints(venue) : 0,
          ...(loyaltyLive ? { earnRate, nextReward: next, nextRewardLine: rewardProgress.nextRewardLine(next) } : {}),
          offers
        }
      });
    }

    // Register card: purchase proof (possession of the physical card is the
    // gate — points come from the venue's owner-configured earn rate).
    // Loyalty pauses gracefully when the owner's business subscription lapses —
    // never a scary error at the register.
    // Both at once; the app offers to save the store when it isn't saved yet
    const [{ earns, demo, status: loyalty }, alreadySaved] = await Promise.all([
      registerScanEarns(venue),
      userHasSavedVenuePlace(userId, venue)
    ]);
    if (!earns) {
      console.warn(`[loyalty-integrity] register scan paused venue=${venue.venueId} reason=${loyalty.reason}`);
      const { rewardPoints, venueBalances } = await rewardService.getBalance(userId, { withEvents: false });
      welcomeAfterScan(userId, venue, 0, 0);
      return res.json({
        success: true,
        data: {
          kind: 'register',
          venue: publicVenueInfo(venue),
          awarded: null,
          loyaltyPaused: true,
          // 'not_started' (owner never subscribed) or 'paused' (it ran out)
          loyaltyState: (await loyaltyNeverStarted(venue)) ? 'not_started' : 'paused',
          loyaltyLive: false,
          saveBonusPoints: 0,
          alreadySaved,
          balance: rewardPoints,
          venueBalance: (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0,
          offers: []
        }
      });
    }
    // Comped venue awarding points has no paying subscriber — surface it so
    // revenue leakage is measurable, not invisible.
    if (demo) {
      console.info(`[loyalty-integrity] demo award (unclaimed store) venue=${venue.venueId}`);
    }
    if (loyalty.reason === 'comp') {
      console.info(`[loyalty-integrity] comped award venue=${venue.venueId} until=${venue.loyaltyCompedUntil || 'open-ended'} reason=${venue.loyaltyCompReason || 'unspecified'}`);
    }

    // Where the phone was (services/scanLocation): clearly away from the
    // store (the app's fix, or the App Clip's Apple check) earns nothing and
    // shows on the owner's Activity; location off still earns, marked
    const location = scanLocationCheck(req.body, venue);
    const notAtStore = location === 'far';
    if (notAtStore) {
      console.warn(`[loyalty-integrity] register scan away from the store venue=${venue.venueId} user=${userId}`);
    }
    const visitResult = notAtStore
      ? { awarded: false, reason: 'not_at_store' }
      : await rewardService.awardVenueVisit(userId, venue, { location });
    // Every scan that earned nothing is on the owner's Activity too, with its
    // time (services/scanAttempts), so scans can be checked against cameras
    if (!visitResult.awarded) {
      await recordScanAttempt(userId, venue, { reason: notAtStore ? 'far' : visitResult.reason, location })
        .catch((e) => console.warn('⚠️ scan attempt not recorded:', e.message));
    }

    const { rewardPoints, venueBalances } = await rewardService.getBalance(userId, { withEvents: false });
    const venueBalance = (venueBalances.find((v) => v.venueId === venue.venueId) || {}).points || 0;
    const offers = activeOffers(venue);
    const earnRate = rewardService.effectiveEarnRate(venue);
    welcomeAfterScan(userId, venue, visitResult.awarded ? visitResult.points : 0, venueBalance);
    return res.json({
      success: true,
      data: {
        kind: 'register',
        venue: publicVenueInfo(venue),
        awarded: visitResult.awarded
          ? { type: 'venue_visit', points: visitResult.points }
          : null,
        alreadyEarnedToday: visitResult.reason === 'already_today',
        ...(notAtStore ? { notAtStore: true } : {}),
        ...(visitResult.reason === 'removed' ? { removedFromRewards: true } : {}),
        alreadySaved,
        balance: rewardPoints,
        venueBalance,
        loyaltyLive: true,
        saveBonusPoints: rewardService.effectiveSavePoints(venue),
        earnRate,
        offers,
        // The store's own terms: how far this balance is from the next reward
        nextReward: rewardProgress.nextReward(offers, venueBalance, earnRate),
        nextRewardLine: rewardProgress.nextRewardLine(rewardProgress.nextReward(offers, venueBalance, earnRate))
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

    // The owner's points for saving the store, once, at a store whose
    // rewards are live: from either code (Wes, 2026-11-01; the window code
    // paid nothing from 2026-10-30 until then)
    const result = (await isVenueLoyaltyActive(venue))
      ? await rewardService.awardStickerSave(userId, venue)
      : { awarded: false, reason: 'not_live' };
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
// @desc    Share your name, photo and email with a store — asked once, before
//          the first reward there (services/storeCustomers)
// @route   POST /api/rewards/venues/:venueId/share
// @access  Private
exports.shareWithStore = async (req, res) => {
  try {
    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(req.params.venueId)).get();
    if (!venueDoc.exists) return res.status(404).json({ success: false, error: 'Store not found' });
    await require('../../services/storeCustomers').shareWithStore(req.user.uid, { venueId: venueDoc.id, ...venueDoc.data() });
    res.json({ success: true, data: { shared: true } });
  } catch (error) {
    console.error('❌ Share with store failed:', error);
    res.status(500).json({ success: false, error: 'Could not share with the store' });
  }
};

// @desc    "Enjoying <store>?" after a reward is given — the card's data the
//          first time only ({ show: false } after that). services/storeFeedback
// @route   POST /api/rewards/venues/:venueId/enjoying
// @access  Private
exports.enjoyingCard = async (req, res) => {
  try {
    const data = await require('../../services/storeFeedback').enjoyingCard(req.user.uid, req.params.venueId);
    res.json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ enjoyingCard failed', fallbackMessage: 'Could not load the card' });
  }
};

// @desc    Private feedback to a store: { rating 1–5, note? }, read only by its team
// @route   POST /api/rewards/venues/:venueId/feedback
// @access  Private
exports.sendStoreFeedback = async (req, res) => {
  try {
    const data = await require('../../services/storeFeedback').sendFeedback(req.user.uid, req.params.venueId, req.body || {});
    res.json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ sendStoreFeedback failed', fallbackMessage: 'Could not send your feedback' });
  }
};

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

    const result = await rewardService.redeemOffer(req.user.uid, venueId, offerId, { askShare: req.body.canShare === true });
    if (!result.success) {
      return res.status(400).json({ success: false, error: result.error, ...(result.code ? { code: result.code } : {}) });
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

    // Apps that show store events under "Happening nearby" ask for them to
    // be left out here (events=1); older apps still get them as announcements
    const eventsSeparately = req.query.events === '1';
    const announcementsFor = (venue) => rewardService.activeAnnouncements(venue)
      .filter((a) => !(eventsSeparately && a.event));

    // A venue belongs in the browse list only while its loyalty is live
    // (listLiveVenues) and it has something to show — a redeemable offer or
    // an announcement.
    const liveVenues = (await listLiveVenues())
      .filter((venue) => isBrowsableBy(venue, userId, { isSuperUser: req.user.isSuperUser === true }))
      .filter((venue) => activeOffers(venue).length > 0 || announcementsFor(venue).length > 0);

    const savedVenueIds = await rewardService.getSavedVenueIds(userId, liveVenues);

    const photoUrls = await fetchVenuePhotoUrls(liveVenues);

    const venues = liveVenues.map((venue) => ({
      ...publicVenueInfo(venue),
      earnRate: rewardService.effectiveEarnRate(venue),
      savedByUser: savedVenueIds.has(venue.venueId),
      photoUrl: photoUrls.get(venue.venueId) || null,
      distanceMeters: hasCoords && venue.location
        ? geofire.distanceBetween([lat, lng], [venue.location.lat, venue.location.lng]) * 1000
        : null,
      offers: activeOffers(venue).map(({ offerId, title, pointsCost }) => ({
        offerId, title, pointsCost
      })),
      announcements: announcementsFor(venue)
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
    const venueBalances = await rewardService.venueBalancesWithNames(userData);

    res.json({
      success: true,
      data: { venues: venues.slice(0, rewardConfig.NEARBY_MAX_VENUES), balance, venueBalances }
    });
  } catch (error) {
    console.error('❌ Failed to load offers:', error);
    res.status(500).json({ success: false, error: 'Failed to load offers' });
  }
};

// @desc    "Happening nearby" for the Locals tab: store events, free library
//          programs, Ticketmaster shows (next two weeks) and the nearest
//          farmers markets. Empty lists when there's no location or a
//          source is down.
// @route   GET /api/rewards/nearby-events?lat=&lng=
// @access  Private
exports.getNearbyEvents = async (req, res) => {
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  // Test stores' events reach their own team and super-users only
  const viewer = { uid: req.user.uid, isSuperUser: req.user.isSuperUser === true };
  const feed = await nearbyEventsService.getLocalFeed(lat, lng, { viewer }).catch((error) => {
    console.error('❌ Failed to load nearby events:', error);
    return { events: [], markets: [], attribution: null };
  });
  res.json({ success: true, data: { ...feed, source: 'ticketmaster' } });
};

// @desc    Search for the Locals tab: every Ticketmaster listing for the words
//          (a year out, 100 miles; anywhere when nothing is near) plus
//          matching store events and library programs.
// @route   GET /api/rewards/nearby-events/search?q=&lat=&lng=
// @access  Private
exports.searchNearbyEvents = async (req, res) => {
  const q = String(req.query.q || '').trim().slice(0, 80);
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const viewer = { uid: req.user.uid, isSuperUser: req.user.isSuperUser === true };
  const result = await nearbyEventsService.searchLocalEvents(q, lat, lng, { viewer }).catch((error) => {
    console.error('❌ Failed to search events:', error);
    return { events: [], nearby: true, attribution: null };
  });
  res.json({ success: true, data: { query: q, ...result } });
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
      // Super-users print any store's codes from its page; a place nobody
      // enrolled gets its venue minted on the way (POST venues/from-place)
      const canPrintCodes = req.user.isSuperUser === true && claim.canClaim;
      return res.json({ success: true, data: { venue: null, claim, canPrintCodes } });
    }

    // The store's team only. A super-user is not the owner (Wes, 2026-10-28):
    // the page keeps its claim card for the real owner, and the super-user
    // reaches the store's codes and tools through "Store Admin".
    const isOwner = isVenueTeamMember(venue, userId);

    // Get Rewards asks for the caller's own history here (?history=1);
    // the place page doesn't, so it pays nothing for it. Never fails the page.
    // It also gets the store's cover photo for its header. Started now so it
    // runs alongside the lookups below.
    const extrasPromise = req.query.history === '1' && !isOwner
      ? Promise.all([
        require('../../services/rewardHistoryService').forUserAtVenue(userId, venue.venueId).catch((historyError) => {
          console.error('⚠️ Reward history lookup failed (page continues):', historyError.message);
          return undefined;
        }),
        require('../../services/storeCoverPhoto').coverUrlFor(venue).catch(() => null)
      ])
      : Promise.resolve([undefined, undefined]);

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

    // The caller's open order-ahead order here, if any: the page shows a
    // "Your order" row that opens its status. Never lets the page fail.
    let myOrders = [];
    try {
      myOrders = await require('../../services/orders/orderService').openOrdersAtVenue(userId, venue.venueId);
    } catch (orderError) {
      console.error('⚠️ Open-order lookup failed (place page continues):', orderError.message);
    }

    // Started up top, alongside everything else
    const [myHistory, coverPhotoUrl] = await extrasPromise;

    res.json({
      success: true,
      data: {
        myHistory,
        venue: {
          ...publicVenueInfo(venue),
          coverPhotoUrl,
          // Rewards exist only once the store is claimed and its owner is on
          // Business (or comped). Until then nothing on the page says "earn":
          // an enrolled-but-unowned store carried its default rate here and
          // the page read it as a rewards program (Wes, 2026-10-28).
          earnRate: venueLoyaltyLive ? rewardService.effectiveEarnRate(venue) : null
        },
        // Whether a register scan here earns right now (the same check the
        // scan makes) — the place page's "Get Rewards" hides when it wouldn't.
        rewardsLive: venueLoyaltyLive,
        // "Ordered for delivery? Send your receipt" (services/receiptClaims)
        deliveryReceipts: venueLoyaltyLive ? require('../../services/receiptClaims').mode(venue) : 'off',
        offers: (venueLoyaltyLive ? activeOffers(venue) : []).map(({ offerId, title, pointsCost }) => ({
          offerId, title, pointsCost
        })),
        announcements: venueLoyaltyLive ? rewardService.activeAnnouncements(venue) : [],
        // Menu / buttons / gallery. Buttons always; the paid blocks only while
        // the store's subscription is live, same as announcements.
        storefront: require('../../services/venueStorefront').publicStorefront(venue, {
          live: venueLoyaltyLive,
          // Order ahead takes a paid Business subscription; a comp doesn't count
          orderingLive: venue.ordering && venue.ordering.enabled === true ? await isVenueBusinessLive(venue) : false
        }),
        balance,
        venueBalance,
        // The store's next reward for this balance (the card's "N more for a free coffee")
        nextReward: venueLoyaltyLive ? rewardProgress.nextReward(activeOffers(venue), venueBalance, rewardService.effectiveEarnRate(venue)) : null,
        myOrders,
        myOrder: myOrders[0] || null,
        // The caller's spot in the store's waitlist, if any (2026-11-09)
        myWaitlist: await require('../../services/waitlistService').mine(venue.venueId, req.user.uid).catch(() => null),
        // Bring a friend: the offer and the caller's own invite link, while it's on (2026-11-09)
        referral: isOwner ? null : require('../../services/storeReferrals').publicReferral(venue, req.user.uid, { live: venueLoyaltyLive }),
        isOwner,
        // Super-users keep the place page's "Store Admin" door once
        // the store is enrolled too (it opens the Store page)
        canPrintCodes: req.user.isSuperUser === true,
        // For the owner viewing their own place: drives the in-place
        // "Upgrade to Business" teaser when they can't post announcements yet
        ownerPremium: isOwner ? isOwnerPremiumForVenue(req.user, venue.venueId, venue) : undefined,
        // Inline stat strip on the owner's place page (headline counters only)
        ownerStats: isOwner ? {
          saves: (venue.stats || {}).saves || 0,
          visits: (venue.stats || {}).visits || 0,
          scans: (venue.stats || {}).scans || 0,
          redemptions: (venue.stats || {}).redemptions || 0,
          // Orders waiting to be accepted (the owner bar's first words)
          orderingEnabled: !!(venue.ordering && venue.ordering.enabled === true),
          newOrders: await require('../../services/orders/orderService').newCount({ ...venue, venueId: venue.venueId })
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
