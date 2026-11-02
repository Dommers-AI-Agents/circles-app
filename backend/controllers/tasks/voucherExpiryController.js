// backend/controllers/tasks/voucherExpiryController.js
//
// Every 5 minutes: reward tickets that ran out without staff tapping
// "Given" expire and their points go back to the customer (2026-11-01).
const { scheduledTask } = require('../../middleware/scheduledTask');
const vouchers = require('../../services/rewardVoucherService');

exports.expire = scheduledTask({
  name: 'reward-tickets-expire', log: '🎟️ Reward ticket expiry triggered via API', failure: 'Reward ticket expiry failed',
  run: async () => vouchers.expireDue()
});
