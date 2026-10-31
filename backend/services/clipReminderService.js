// backend/services/clipReminderService.js
// One reminder from the App Clip (Wes, 2026-10-31). An App Clip may notify
// for 8 hours after it's used, with no permission prompt. Two hours after a
// clip sign-in, if the person still hasn't installed FavCircles, one push:
// what they earned at the store and why the app is worth it. Never more.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');

const COLLECTION = 'clipDevices';
const SEND_AFTER_MS = 2 * 60 * 60 * 1000;
const WINDOW_MS = 8 * 60 * 60 * 1000; // Apple's ephemeral notification window
const CLIP_TOPIC = 'com.favcircles.circles.Clip';

/** The clip's APNs token for this user, with the code it opened on. */
async function registerDevice(userId, { token, code, environment }, { now = Date.now(), db = getFirestore() } = {}) {
  const deviceToken = String(token || '').trim();
  if (!/^[0-9a-fA-F]{32,200}$/.test(deviceToken)) throw new ServiceError(400, 'TOKEN_INVALID', 'A device token is required.');
  const ref = db.collection(COLLECTION).doc(userId);
  const existing = await ref.get();
  // The same clip launch registering again keeps its place in line; an
  // already-sent reminder stays sent (one per person, ever)
  if (existing.exists && (existing.data().sent || existing.data().token === deviceToken)) {
    if (!existing.data().sent) await ref.update({ code: String(code || '').toUpperCase() || existing.data().code });
    return { registered: true };
  }
  await ref.set({
    token: deviceToken,
    code: String(code || '').toUpperCase() || null,
    environment: environment === 'development' ? 'development' : 'production',
    createdAt: now,
    sendAfter: now + SEND_AFTER_MS,
    sent: false
  });
  return { registered: true };
}

/** The words, from where they are with the store (pure, tested). */
function reminderFor({ venue, venuePoints }) {
  if (!venue || venue.genericJoin) {
    return { title: 'FavCircles', body: 'Get FavCircles to start your map.' };
  }
  return venuePoints > 0
    ? { title: venue.venueName, body: 'Your points are saved. Get FavCircles to see your rewards and keep earning.' }
    : { title: venue.venueName, body: `Get FavCircles to keep ${venue.venueName} on your map.` };
}

/** Rows due now: past their two hours, inside the 8-hour window, unsent (pure, tested). */
const isDue = (row, now) => !row.sent && row.sendAfter <= now && now - row.createdAt < WINDOW_MS;

/** The scheduled run: sends what's due, to people who haven't installed the app. */
async function sendDue({ now = Date.now(), db = getFirestore(), deps = {} } = {}) {
  const apns = deps.apns || require('./apnsDirect');
  const rewardService = deps.rewardService || require('./rewardService');
  if (!apns.configured()) return { skipped: 'APNs key not configured', sent: 0 };
  const snap = await db.collection(COLLECTION).where('sent', '==', false).get();
  let sent = 0; let installed = 0; let expired = 0;
  for (const doc of snap.docs) {
    const row = doc.data();
    if (now - row.createdAt >= WINDOW_MS) { await doc.ref.update({ sent: true, outcome: 'expired' }); expired += 1; continue; }
    if (!isDue(row, now)) continue;
    const user = await db.collection(COLLECTIONS.USERS).doc(doc.id).get();
    if (!user.exists || user.data().clipInstallConvertedAt) {
      await doc.ref.update({ sent: true, outcome: 'installed' }); installed += 1; continue;
    }
    const venue = row.code ? await rewardService.findVenueByCode(row.code) : null;
    const balances = rewardService.venueBalancesFrom(user.data()) || [];
    const venuePoints = venue ? ((balances.find((b) => b.venueId === venue.venueId) || {}).points || 0) : 0;
    const { title, body } = reminderFor({ venue, venuePoints });
    const result = await apns.sendAlert({
      deviceToken: row.token, topic: CLIP_TOPIC, title, body,
      environment: row.environment, expiresAt: row.createdAt + WINDOW_MS
    });
    await doc.ref.update({ sent: true, outcome: result === true ? 'sent' : (result === 'gone' ? 'gone' : 'failed'), sentAt: now });
    if (result === true) sent += 1;
  }
  return { sent, installed, expired };
}

module.exports = { registerDevice, reminderFor, isDue, sendDue, CLIP_TOPIC, SEND_AFTER_MS, WINDOW_MS };
