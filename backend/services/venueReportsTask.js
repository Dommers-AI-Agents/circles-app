// backend/services/venueReportsTask.js
//
// Monthly sticker-venue report emails: one per active venue with a contact
// address, for the month that just ended. Was inline in routes/taskRoutes.js.
const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const emailService = require('./emailService');

async function sendVenueReports(now = new Date()) {
  const db = getFirestore();
  const prevMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const monthKey = prevMonth.toISOString().slice(0, 7);
  const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).where('active', '==', true).get();
  let sent = 0;
  let skipped = 0;
  const failures = [];
  for (const doc of snapshot.docs) {
    const venue = { venueId: doc.id, ...doc.data() };
    if (!venue.contactEmail) { skipped++; continue; }
    try {
      const stats = (venue.statsMonthly && venue.statsMonthly[monthKey]) || {};
      await emailService.sendVenueReportEmail(venue, monthKey, stats);
      await doc.ref.update({ lastReportSentAt: new Date().toISOString() });
      sent++;
    } catch (error) {
      console.error(`❌ Venue report failed for ${venue.venueName}:`, error.message);
      failures.push(venue.venueName);
    }
  }
  return { monthKey, sent, skipped, failures };
}

module.exports = { sendVenueReports };
