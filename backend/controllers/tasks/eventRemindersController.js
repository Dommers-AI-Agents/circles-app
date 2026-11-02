// backend/controllers/tasks/eventRemindersController.js
//
// Hourly: the day-before reminder for events with a start time (email to
// guests who said Going/Maybe, push to members). Each event is claimed in a
// transaction before sending, so a retry or overlap never repeats it
// (services/eventGuestService.sendDueReminders).
const { scheduledTask } = require('../../middleware/scheduledTask');
const guests = require('../../services/eventGuestService');

exports.send = scheduledTask({
  name: 'event-reminders', log: '🎟️ Event reminders triggered via API', failure: 'Event reminders failed',
  run: async () => ({ message: 'Event reminders done', ...(await guests.sendDueReminders()) })
});
