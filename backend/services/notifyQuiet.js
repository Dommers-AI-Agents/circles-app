// backend/services/notifyQuiet.js
//
// Fire-and-forget push for notices nothing depends on. Stamps `data.type`
// with the top-level type (tap routing reads it there) and swallows the
// failure with a log line, so a push can never fail the thing it describes.
const notificationService = require('./notificationService');

function sendInBackground(userId, { type, title, body, data }, label = type) {
  Promise.resolve(notificationService.sendToUser(userId, { type, title, body, data: { type, ...(data || {}) } }))
    .catch((error) => console.error(`[${label}] push failed for ${userId}: ${error.message}`));
}

module.exports = { sendInBackground };
