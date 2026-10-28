// backend/controllers/tasks/appClipSyncController.js
//
// Nightly: every live store gets (or keeps) its own App Clip cards in App
// Store Connect — name, points and cover photo on the card a scan shows
// (services/appClipExperienceService). Idempotent: a store whose card
// already matches is skipped; ?limit= caps how many are published per run.
const { scheduledTask } = require('../../middleware/scheduledTask');
const { listLiveVenues } = require('../../services/liveVenues');
const appClipExperiences = require('../../services/appClipExperienceService');

exports.sync = scheduledTask({
  name: 'app-clip-sync', log: '📎 App Clip card sync triggered via API', failure: 'App Clip card sync failed',
  run: async (req) => {
    const limit = Math.max(1, Math.min(parseInt(req.query.limit, 10) || 25, 200));
    const venues = (await listLiveVenues()).filter((v) => !v.isTestStore);
    let published = 0; let skipped = 0; const failed = [];
    for (const venue of venues) {
      if (published >= limit) break;
      try {
        const result = await appClipExperiences.syncVenue(venue);
        if (result.changed && result.changed.length) published += 1; else skipped += 1;
      } catch (error) {
        failed.push({ venueId: venue.venueId, error: error.message });
      }
    }
    return { message: 'App Clip card sync completed', venues: venues.length, published, skipped, failed };
  }
});
