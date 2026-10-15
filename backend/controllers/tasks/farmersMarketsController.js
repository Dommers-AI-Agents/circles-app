// Monthly: refresh the USDA farmers market directory copy the Locals tab
// reads (services/localEvents/farmersMarkets.js).
const { scheduledTask } = require('../../middleware/scheduledTask');
const { syncUsdaMarkets } = require('../../services/localEvents/farmersMarkets');

exports.sync = scheduledTask({
  name: 'farmers-markets-sync',
  log: '🥕 Syncing the USDA farmers market directory',
  failure: 'Farmers market sync failed',
  run: async () => ({ result: await syncUsdaMarkets() })
});
