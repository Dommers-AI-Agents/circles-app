// controllers/venues/venueOffersController.js
// Owner specials: offers and announcements
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { validateOfferInput, validateAnnouncementInput, STICKER_COLLECTIONS, MAX_ANNOUNCEMENTS } = require('../../models/StickerModels');
const { createActivity } = require('../activityController');
const sseService = require('../../services/sseService');
const db = getFirestore();
// Announcements expired this long ago get pruned on the next write, keeping
// the embedded array (and the venue doc) small permanently.
const PRUNE_EXPIRED_AFTER_MS = 30 * 24 * 60 * 60 * 1000;
const { venueGlobalPlaceId } = require('../../services/venueHelpers.js');

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
