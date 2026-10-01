// One channel for "the admin should know about this": an email to
// ADMIN_ALERT_EMAIL and a push + bell row to the admin account. Before this,
// admin alerts used three env vars with three defaults, push alerts silently
// did nothing when no account matched, and failed jobs, webhook errors,
// 5xx spikes and signup bursts alerted nobody (security audit 2026-10-01).
//
// alertAdmin({ key, title, body }) — `key` de-duplicates: the same key sends
// at most once per `minIntervalMs` (default 1 h); repeats in between are
// counted and reported in the next alert. Never throws.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const ALERT_EMAIL = () => process.env.ADMIN_ALERT_EMAIL || process.env.MODERATION_ALERT_EMAIL || 'wesley@favcircles.com';
const ADMIN_ACCOUNT_EMAIL = () => process.env.ADMIN_NOTIFY_EMAIL || 'sgroiwes@gmail.com';
const HOUR = 60 * 60 * 1000;

async function claimSlot(db, key, minIntervalMs, now) {
  const ref = db.collection('adminAlerts').doc(String(key).replace(/[/\s]/g, '_').slice(0, 300));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists ? snap.data() : {};
    const last = prev.lastSentAt ? Date.parse(prev.lastSentAt) : 0;
    if (minIntervalMs > 0 && now - last < minIntervalMs) {
      tx.set(ref, { suppressed: (prev.suppressed || 0) + 1, lastSeenAt: new Date(now).toISOString() }, { merge: true });
      return null;
    }
    tx.set(ref, { lastSentAt: new Date(now).toISOString(), lastSeenAt: new Date(now).toISOString(), suppressed: 0 }, { merge: true });
    return { suppressed: prev.suppressed || 0 };
  });
}

async function alertAdmin({ key, title, body, minIntervalMs = HOUR, push = true, email = true }, deps = {}) {
  try {
    const db = deps.db || getFirestore();
    const slot = await claimSlot(db, key, minIntervalMs, Date.now());
    if (!slot) return false;
    const fullBody = slot.suppressed ? `${body}\n\n(+${slot.suppressed} more like this since the last alert)` : body;

    if (email) {
      const emailService = deps.emailService || require('./emailService');
      await emailService.sendEmail({ to: ALERT_EMAIL(), subject: `[FavCircles] ${title}`, text: fullBody, html: `<pre style="font:13px/1.5 -apple-system,Menlo,monospace;white-space:pre-wrap">${require('../utils/text').escapeHtml(fullBody)}</pre>` })
        .catch((e) => console.error(`[admin-alert] email failed (${key}): ${e.message}`));
    }
    if (push) {
      const admin = await db.collection(COLLECTIONS.USERS).where('email', '==', ADMIN_ACCOUNT_EMAIL()).limit(1).get();
      if (admin.empty) {
        console.error(`[admin-alert] no account for ADMIN_NOTIFY_EMAIL ${ADMIN_ACCOUNT_EMAIL()} — push skipped`);
      } else {
        const notificationService = deps.notificationService || require('./notificationService');
        await notificationService.sendToUserWithRecord(admin.docs[0].id, { type: 'admin_alert', title, body: fullBody.slice(0, 500), data: { key: String(key) } })
          .catch((e) => console.error(`[admin-alert] push failed (${key}): ${e.message}`));
      }
    }
    console.warn(`[admin-alert] ${key}: ${title}`);
    return true;
  } catch (error) {
    console.error(`[admin-alert] failed (${key}): ${error.message}`);
    return false;
  }
}

module.exports = { alertAdmin };
