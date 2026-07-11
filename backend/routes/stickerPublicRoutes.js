// backend/routes/stickerPublicRoutes.js
// Public smart-landing page for physical sticker QR codes.
//
// With the app installed, iOS opens /s/<code> as a Universal Link (AASA paths
// include /s/*) and this handler is never hit. Without the app, this page
// tries the circles:// scheme (covers in-app browsers that block Universal
// Links) and then falls back to the App Store, mirroring GET /connect/:userId.

const express = require('express');
const router = express.Router();
const rewardService = require('../services/rewardService');
const rewardConfig = require('../config/rewardConfig');

router.get('/:code', async (req, res) => {
  const code = String(req.params.code).replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
  const appStoreUrl = rewardConfig.APP_STORE_URL;

  let venueName = 'This place';
  try {
    const venue = await rewardService.findVenueByCode(code);
    if (venue && venue.active !== false) {
      venueName = venue.venueName;
      // A landing-page hit means the app wasn't installed — count the scan.
      // (Installed-app scans are counted by POST /api/rewards/scan.)
      rewardService.incrementVenueStats(venue.venueId, 'scans');
    }
  } catch (error) {
    console.error('⚠️ Sticker landing lookup failed:', error.message);
  }

  const safeVenueName = venueName.replace(/[<>&"]/g, '');

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${safeVenueName} on FavCircles</title></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center">
<div style="padding:24px">
<div style="font-size:56px;margin-bottom:8px">&#128205;</div>
<h1 style="margin:0 0 8px">Don't forget ${safeVenueName}!</h1>
<p style="margin:0 0 20px;opacity:.9">Save this place on FavCircles and earn rewards<br>you can use on your next visit.</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Get the App &amp; Earn Rewards</a>
</div>
<script>
  window.location = 'circles://sticker?code=${code}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

module.exports = router;
