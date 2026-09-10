// controllers/venues/redemptionCodeController.js
// Redemption codes: create, list, redeem
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { createRedemptionCode, validateRedemptionCodeBatch, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const { isOwnerPremiumForVenue, isCompActive } = require('../../services/ownerSubscriptionService');
const db = getFirestore();
const piggyBankService = require('../../services/piggyBankService');
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
