// backend/controllers/tasks/appClipSyncController.js
//
// Nightly: every live store gets (or keeps) its own App Clip cards in App
// Store Connect — name, points and cover photo on the card a scan shows
// (services/appClipExperienceService). Idempotent: a store whose card
// already matches is skipped; ?limit= caps how many are published per run.
const { scheduledTask } = require('../../middleware/scheduledTask');
const { getFirestore } = require('../../config/firebase');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const { listLiveVenues } = require('../../services/liveVenues');
const appClipExperiences = require('../../services/appClipExperienceService');

// Every enrolled store gets both cards (Wes, 2026-10-29: the generic card is
// only for codes no store owns); the register card promises points only
// where the loyalty program is live, and republishes the night it goes live.
exports.sync = scheduledTask({
  name: 'app-clip-sync', log: '📎 App Clip card sync triggered via API', failure: 'App Clip card sync failed',
  run: async (req) => {
    const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 25, 200));
    const snapshot = await getFirestore().collection(STICKER_COLLECTIONS.STICKER_VENUES).get();
    // Test stores too (Wes, 2026-10-29): their codes are only in his hands,
    // and the cards are how the real scan is checked before a store launches
    const venues = snapshot.docs.map((d) => ({ venueId: d.id, ...d.data() }));
    const live = new Set((await listLiveVenues()).map((v) => v.venueId));
    let published = 0; let skipped = 0; const failed = [];
    for (const venue of venues) {
      if (published >= limit) break;
      try {
        // The register card promises points wherever a register scan earns
        // them: live loyalty, or an unclaimed store's demo
        const result = await appClipExperiences.syncVenue(venue, { live: live.has(venue.venueId) || !venue.ownerUserId });
        if (result.changed && result.changed.length) published += 1; else skipped += 1;
      } catch (error) {
        console.error('⚠️ App Clip card sync failed for', venue.venueId, venue.venueName, '-', error.message);
        failed.push({ venueId: venue.venueId, error: error.message });
      }
    }
    return { message: 'App Clip card sync completed', venues: venues.length, published, skipped, failed };
  }
});
