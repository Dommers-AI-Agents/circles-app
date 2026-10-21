// backend/controllers/tasks/ordersSweepController.js
//
// Every 5 minutes: order-ahead orders nobody at the store answered in 30
// minutes expire (the customer is told not to head over); ready orders
// nobody closed in 12 hours are closed (services/orders).
const { scheduledTask } = require('../../middleware/scheduledTask');
const orders = require('../../services/orders/orderService');

exports.sweep = scheduledTask({
  name: 'orders-sweep', log: '🧾 Orders sweep triggered via API', failure: 'Failed to sweep orders',
  run: async () => ({ message: 'Orders swept', ...(await orders.sweep()) })
});
