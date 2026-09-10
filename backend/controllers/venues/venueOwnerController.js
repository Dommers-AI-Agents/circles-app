// controllers/venues/venueOwnerController.js
// Owner dashboard: requireVenueOwner middleware, my venues, dashboard, audience, cover photo, venue info/settings, register code
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { validateEarnRate, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const emailService = require('../../services/emailService');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');
const { isOwnerPremiumUser, isOwnerPremiumForVenue, isOwnerPremiumById } = require('../../services/ownerSubscriptionService');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const db = getFirestore();
const { venueManagerIds, isVenueTeamMember, venueGlobalPlaceId } = require('../../services/venueHelpers.js');

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
  ownerUserId: venue.ownerUserId || null,
  managerUserIds: venueManagerIds(venue),
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
    if (!isVenueTeamMember(venue, req.user.uid) && req.user.isSuperUser !== true) {
      return res.status(403).json({ success: false, error: 'You do not manage this venue' });
    }
    req.venue = venue;
    // Some team actions (managing the managers) stay with the billing owner
    req.isPrimaryVenueOwner = !!venue.ownerUserId && isSameUser(venue.ownerUserId, req.user.uid);
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

    // Venues this user manages for someone else ride along with the ones
    // they own (same list, same tools; billing stays with the owner)
    const managedSnap = await venuesRef
      .where('managerUserIds', 'array-contains', uid).get();
    managedSnap.docs.forEach((doc) => {
      if (!venues.some((v) => v.venueId === doc.id)) {
        venues.push({ venueId: doc.id, ...doc.data() });
      }
    });

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
    await Promise.all(venueInfos.map(async (info, i) => {
      const venue = venues[i];
      info.isPrimaryOwner = !!venue.ownerUserId && isSameUser(venue.ownerUserId, uid);
      // A manager's tools unlock on the BILLING owner's subscription — the
      // store is subscribed, not the person tapping
      info.ownerPremium = info.isPrimaryOwner || !venue.ownerUserId
        ? isOwnerPremiumForVenue(req.user, venue.venueId, venue)
        : await isOwnerPremiumById(venue.ownerUserId, venue.venueId, venue);
    }));
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
    // consumer savers list in placeSocialController.getPlaceSavers)
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
    const venuesRef = db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
    const owned = await venuesRef.where('ownerUserId', '==', uid).limit(1).get();
    const managed = owned.empty
      ? await venuesRef.where('managerUserIds', 'array-contains', uid).limit(1).get()
      : owned;
    if (owned.empty && managed.empty && req.user.isSuperUser !== true) {
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
      const { buildSearchTokens } = require('../../models/GlobalPlace');
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
      // ownerEmail mirrors contactEmail (used for lazy claim-by-email) —
      // but only when the billing owner (or an admin) edits it: a manager
      // shouldn't be able to repoint the ownership-claim email
      if (req.isPrimaryVenueOwner === true || req.user.isSuperUser === true) {
        update.ownerEmail = update.contactEmail;
      }
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
