// backend/controllers/tasks/storeAutomationsController.js
//
// Daily: every Business store's automatic nudges — win-back, birthday, one
// more visit to a reward (services/storeAutomations). Idempotent: each send
// is a doc created once. `?dryRun=1` answers with what would go, sending
// and writing nothing.
const { scheduledTask } = require('../../middleware/scheduledTask');
const automations = require('../../services/storeAutomations');

exports.run = scheduledTask({
  name: 'store-automations', log: '🛎 Store automations triggered via API', failure: 'Store automations failed',
  run: async (req) => ({
    message: 'Store automations done',
    ...(await automations.runDue({ dryRun: ['1', 'true'].includes(String((req.query || {}).dryRun || '')) }))
  })
});
