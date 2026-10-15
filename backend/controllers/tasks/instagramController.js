// backend/controllers/tasks/instagramController.js
//
// Daily (noon New York): renew the Instagram token when due, then publish
// the next approved post (services/instagramPublisher.js). ?force=true posts
// even if one already went out today (manual runs).
const { scheduledTask } = require('../../middleware/scheduledTask');
const { createPublisher } = require('../../services/instagramPublisher');

exports.post = scheduledTask({
  name: 'instagram-post', log: '📸 Instagram post job triggered via API', failure: 'Instagram post job failed',
  run: async (req) => {
    const publisher = createPublisher();
    const token = await publisher.refreshTokenIfDue();
    const result = await publisher.publishNext({ force: req.query.force === 'true' });
    return { token, ...result };
  }
});
