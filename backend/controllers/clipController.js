// backend/controllers/clipController.js
// App Clip support endpoints.
//
// The App Clip claims /s/* via the AASA appclips key, so QR scans on iOS open
// the clip instead of the HTML landing page. The clip is unauthenticated until
// the user signs up, so the venue preview here is public — keep the projection
// minimal (no codes, owner contact info, stats, or place IDs).

const rewardService = require('../services/rewardService');
const rewardConfig = require('../config/rewardConfig');

// GET /api/clip/venue/:code — public offer-screen data for the clip.
// Counts a clipScan (top of the clip funnel). Preview refetches on clip
// relaunch each count one — accepted slop, it's a directional metric.
exports.getVenuePreview = async (req, res) => {
  try {
    const code = String(req.params.code || '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
    if (!code) {
      return res.status(400).json({ success: false, error: 'Missing code' });
    }

    const venue = await rewardService.findVenueByCode(code);
    if (!venue || venue.active === false) {
      return res.status(404).json({ success: false, error: 'Unknown code' });
    }

    rewardService.incrementVenueStats(venue.venueId, 'clipScans');

    return res.json({
      success: true,
      data: {
        venueName: venue.venueName,
        placeName: venue.placeName || null,
        placeAddress: venue.placeAddress || null,
        category: venue.category || null,
        kind: venue.kind, // 'window' | 'register'
        signupBonusPoints: rewardConfig.POINTS.STICKER_SIGNUP
      }
    });
  } catch (error) {
    console.error('⚠️ Clip venue preview failed:', error.message);
    return res.status(500).json({ success: false, error: 'Something went wrong' });
  }
};

// POST /api/clip/install-converted — the full app calls this once on first
// launch when it adopted clip credentials. Idempotent per user; a successful
// no-op for organic users so the client never needs to special-case.
exports.installConverted = async (req, res) => {
  try {
    const userId = req.user.uid;
    const outcome = await rewardService.markClipInstallConverted(userId);
    return res.json({ success: true, ...outcome });
  } catch (error) {
    console.error('⚠️ Clip install conversion failed:', error.message);
    return res.status(500).json({ success: false, error: 'Something went wrong' });
  }
};
