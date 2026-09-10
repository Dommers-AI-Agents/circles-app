// controllers/venues/venueManagersController.js
// Venue team: list/add/remove managers
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const { isSameUser } = require('../../services/idService');
const MAX_VENUE_MANAGERS = 10;
const db = getFirestore();
const { venueManagerIds } = require('../../services/venueHelpers.js');

// ---------- Venue managers (multi-user store management) ----------

// Resolve a set of user ids to lightweight rows for the managers UI
const managerRows = async (userIds) => {
  const rows = await Promise.all(userIds.map(async (id) => {
    try {
      const doc = await db.collection(COLLECTIONS.USERS).doc(id).get();
      const u = doc.exists ? doc.data() : {};
      return {
        userId: id,
        displayName: u.displayName || u.name || null,
        email: u.email || null,
        profilePicture: u.profilePicture || u.picture || null
      };
    } catch (error) {
      return { userId: id, displayName: null, email: null, profilePicture: null };
    }
  }));
  return rows;
};

// @desc    The venue's team: billing owner + managers
// @route   GET /api/rewards/venues/:venueId/managers
// @access  Venue team (requireVenueOwner)
exports.listVenueManagers = async (req, res) => {
  try {
    const venue = req.venue;
    const owner = venue.ownerUserId ? await managerRows([venue.ownerUserId]) : [];
    const managers = await managerRows(venueManagerIds(venue));
    res.json({
      success: true,
      data: {
        owner: owner[0] || null,
        managers,
        canManage: req.isPrimaryVenueOwner === true || req.user.isSuperUser === true,
        maxManagers: MAX_VENUE_MANAGERS
      }
    });
  } catch (error) {
    console.error('❌ Failed to list venue managers:', error);
    res.status(500).json({ success: false, error: 'Failed to load managers' });
  }
};

// @desc    Invite another FavCircles account to manage this store
// @route   POST /api/rewards/venues/:venueId/managers   body: { email }
// @access  Primary owner (or super user)
exports.addVenueManager = async (req, res) => {
  try {
    if (req.isPrimaryVenueOwner !== true && req.user.isSuperUser !== true) {
      return res.status(403).json({ success: false, error: 'Only the store owner can add managers' });
    }
    const venue = req.venue;
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!email) {
      return res.status(400).json({ success: false, error: 'An email address is required' });
    }
    const managerUserId = await rewardService.resolveOwnerUserId(email);
    if (!managerUserId) {
      return res.status(404).json({
        success: false,
        error: 'No FavCircles account uses that email — ask them to sign up first, then add them'
      });
    }
    if (venue.ownerUserId && isSameUser(venue.ownerUserId, managerUserId)) {
      return res.status(400).json({ success: false, error: 'That account already owns this store' });
    }
    const current = venueManagerIds(venue);
    if (current.some((id) => isSameUser(id, managerUserId))) {
      return res.status(400).json({ success: false, error: 'That account already manages this store' });
    }
    if (current.length >= MAX_VENUE_MANAGERS) {
      return res.status(400).json({ success: false, error: `A store can have at most ${MAX_VENUE_MANAGERS} managers` });
    }
    const managerUserIds = [...current, managerUserId];
    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId)
      .update({ managerUserIds, updatedAt: new Date().toISOString() });
    res.json({ success: true, data: { managers: await managerRows(managerUserIds) } });
  } catch (error) {
    console.error('❌ Failed to add venue manager:', error);
    res.status(500).json({ success: false, error: 'Failed to add manager' });
  }
};

// @desc    Remove a manager (owner removes anyone; a manager may remove themself)
// @route   DELETE /api/rewards/venues/:venueId/managers/:managerId
// @access  Primary owner, super user, or the manager themself
exports.removeVenueManager = async (req, res) => {
  try {
    const venue = req.venue;
    const managerId = req.params.managerId;
    const removingSelf = isSameUser(managerId, req.user.uid);
    if (req.isPrimaryVenueOwner !== true && req.user.isSuperUser !== true && !removingSelf) {
      return res.status(403).json({ success: false, error: 'Only the store owner can remove managers' });
    }
    const current = venueManagerIds(venue);
    const managerUserIds = current.filter((id) => !isSameUser(id, managerId));
    if (managerUserIds.length === current.length) {
      return res.status(404).json({ success: false, error: 'That account does not manage this store' });
    }
    await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId)
      .update({ managerUserIds, updatedAt: new Date().toISOString() });
    res.json({ success: true, data: { managers: await managerRows(managerUserIds) } });
  } catch (error) {
    console.error('❌ Failed to remove venue manager:', error);
    res.status(500).json({ success: false, error: 'Failed to remove manager' });
  }
};
