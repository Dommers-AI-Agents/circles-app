// backend/controllers/tasks/receiptExpiryController.js
//
// Daily: delivery receipts nobody at the store answered in 7 days expire,
// and the customer is told (services/receiptClaims).
const { scheduledTask } = require('../../middleware/scheduledTask');
const receiptClaims = require('../../services/receiptClaims');

exports.sweep = scheduledTask({
  name: 'receipts-expire', log: '🧾 Receipt expiry triggered via API', failure: 'Failed to expire receipts',
  run: async () => ({ message: 'Receipts expired', ...(await receiptClaims.expireOld()) })
});
