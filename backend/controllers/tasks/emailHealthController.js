// backend/controllers/tasks/emailHealthController.js
//
// Hourly: log in to the main mail server and the SES backup (no email sent)
// and alert the admin if either can't — so an outage is caught even in a
// quiet hour with nothing sending (services/emailHealth.js).
const { scheduledTask } = require('../../middleware/scheduledTask');
const { healthCheck } = require('../../services/emailHealth');

exports.check = scheduledTask({
  name: 'email-health', log: '📧 Email health check triggered via API', failure: 'Email health check failed',
  run: async () => ({ message: 'Email health check completed', ...(await healthCheck()) })
});
