// backend/controllers/tasks/clipRemindersController.js
//
// Every 15 minutes: the App Clip's one reminder push, two hours after a
// clip sign-in, to people who still haven't installed FavCircles
// (services/clipReminderService). Idempotent: a row is marked sent first time.
const { scheduledTask } = require('../../middleware/scheduledTask');
const clipReminders = require('../../services/clipReminderService');

exports.send = scheduledTask({
  name: 'clip-reminders', log: '📎 App Clip reminders triggered via API', failure: 'App Clip reminders failed',
  run: async () => ({ message: 'App Clip reminders done', ...(await clipReminders.sendDue()) })
});
