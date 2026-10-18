// backend/controllers/tasks/momentExpiryController.js
//
// Every 15 minutes: delete disappearing moments whose 24 hours are up —
// files, likes, comments, views and activity rows (services/momentExpiry.js).
const { getStorage } = require('firebase-admin/storage');
const { scheduledTask } = require('../../middleware/scheduledTask');
const momentExpiry = require('../../services/momentExpiry');

exports.sweep = scheduledTask({
  name: 'moments-expire', log: '⏱ Disappearing moments sweep triggered via API', failure: 'Failed to delete expired moments',
  run: async () => {
    const result = await momentExpiry.sweep({ bucket: getStorage().bucket() });
    return { message: 'Expired moments deleted', ...result };
  }
});
