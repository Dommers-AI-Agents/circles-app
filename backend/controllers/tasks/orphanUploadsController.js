// backend/controllers/tasks/orphanUploadsController.js
//
// Hourly: abandon moment uploads that never finished and delete their bytes
// (services/orphanUploadSweeper.js). ?dryRun=true reports only;
// ?maxPerRun=<n> lowers or raises the per-run cap for a manual run.
const { scheduledTask } = require('../../middleware/scheduledTask');
const { sweepOrphanUploads } = require('../../services/orphanUploadSweeper');

exports.sweep = scheduledTask({
  name: 'orphan-uploads', log: '🧹 Orphan upload sweep triggered via API', failure: 'Failed to sweep orphaned uploads',
  run: async (req) => {
    const dryRun = req.query.dryRun === 'true';
    const cap = parseInt(req.query.maxPerRun, 10);
    const result = await sweepOrphanUploads({ dryRun, ...(Number.isFinite(cap) && cap > 0 ? { maxPerRun: Math.min(cap, 1000) } : {}) });
    return { message: dryRun ? 'Orphan upload sweep dry run completed' : 'Orphan upload sweep completed', ...result };
  }
});
