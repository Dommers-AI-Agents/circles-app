// backend/services/venueReportsTask.js
//
// Monthly store report emails, for the month that just ended: one per active
// store, to its contact address or else its owner's account email (Wes,
// 2026-11-06: the job was never scheduled, and only demo stores had a
// contact address). A month with nothing to report sends nothing.
const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { COLLECTIONS } = require('../models/FirestoreModels');
const emailService = require('./emailService');

/** The month's numbers, App Clip scans and signups counted in. Pure. */
const monthStats = (venue, monthKey) => {
  const raw = (venue.statsMonthly && venue.statsMonthly[monthKey]) || {};
  return {
    scans: (raw.scans || 0) + (raw.clipScans || 0),
    signups: (raw.signups || 0) + (raw.clipSignups || 0),
    saves: raw.saves || 0,
    visits: raw.visits || 0,
    redemptions: raw.redemptions || 0
  };
};

const hasActivity = (stats) => Object.values(stats).some((n) => n > 0);

/** The store's contact address, else its owner's account email. */
async function reportAddress(db, venue) {
  if (venue.contactEmail) return venue.contactEmail;
  if (!venue.ownerUserId) return null;
  const owner = await db.collection(COLLECTIONS.USERS).doc(String(venue.ownerUserId)).get();
  const email = owner.exists ? String(owner.data().email || '').trim() : '';
  return email && !email.endsWith('@privaterelay.appleid.com') ? email : null;
}

async function sendVenueReports(now = new Date()) {
  const db = getFirestore();
  const prevMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const monthKey = prevMonth.toISOString().slice(0, 7);
  const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).where('active', '==', true).get();
  let sent = 0;
  let skipped = 0;
  let quiet = 0;
  const failures = [];
  for (const doc of snapshot.docs) {
    const venue = { venueId: doc.id, ...doc.data() };
    if (venue.lastReportMonth === monthKey) continue; // a rerun never sends twice
    const stats = monthStats(venue, monthKey);
    if (!hasActivity(stats)) { quiet++; continue; }
    try {
      const to = await reportAddress(db, venue);
      if (!to) { skipped++; continue; }
      await emailService.sendVenueReportEmail({ ...venue, contactEmail: to }, monthKey, stats);
      await doc.ref.update({ lastReportSentAt: new Date().toISOString(), lastReportMonth: monthKey });
      sent++;
    } catch (error) {
      console.error(`❌ Venue report failed for ${venue.venueName}:`, error.message);
      failures.push(venue.venueName);
    }
  }
  return { monthKey, sent, skipped, quiet, failures };
}

module.exports = { sendVenueReports, monthStats, hasActivity };
