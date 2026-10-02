// Email delivery health for the admin dashboard, plus alerts when it breaks
// (Wes, 2026-10-02: "status of email smtp and alert me if emails are failing").
//
// Every send outcome lands in a per-day counter doc, emailStats/{YYYY-MM-DD}:
//   primarySent  — delivered by the main server (mail.favcircles.com)
//   fallbackSent — the main server refused/was down; Amazon SES delivered it
//   failed       — neither route delivered it
//   suppressed   — skipped on purpose (bounced address on the do-not-email list)
// with the last few failures kept on the doc for the dashboard table.
// Recording never blocks or fails a send.
const { getFirestore, admin } = require('../config/firebase');
const { maskEmail } = require('../utils/text');

const COLLECTION = 'emailStats';
const RECENT_FAILURES = 20;
const dayKey = (d = new Date()) => d.toISOString().slice(0, 10);

const firstAddress = (to) => (Array.isArray(to) ? to[0] : String(to || '').split(',')[0]).trim();

/** outcome: 'primary' | 'fallback' | 'failed' | 'suppressed' */
async function record(outcome, { to, subject, error, primaryError } = {}, deps = {}) {
  // Unit tests exercise sends with fake transports; never write real counters
  if (process.env.JEST_WORKER_ID && !deps.db) return;
  try {
    const db = deps.db || getFirestore();
    const FieldValue = deps.FieldValue || admin.firestore.FieldValue;
    const field = { primary: 'primarySent', fallback: 'fallbackSent', failed: 'failed', suppressed: 'suppressed' }[outcome];
    if (!field) return;
    const ref = db.collection(COLLECTION).doc(dayKey());
    const now = new Date().toISOString();
    if (outcome === 'failed' || outcome === 'fallback') {
      // Rare: keep the detail for the dashboard (read-modify-write, capped)
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const prev = snap.exists ? snap.data() : {};
        const entry = { at: now, to: maskEmail(firstAddress(to)), subject: String(subject || '').slice(0, 120),
          error: String((error && error.message) || primaryError || '').slice(0, 300), route: outcome };
        const key = outcome === 'failed' ? 'recentFailures' : 'recentFallbacks';
        tx.set(ref, {
          day: dayKey(), [field]: (prev[field] || 0) + 1, [key]: [entry, ...(prev[key] || [])].slice(0, RECENT_FAILURES),
          updatedAt: now
        }, { merge: true });
      });
    } else {
      await ref.set({ day: dayKey(), [field]: FieldValue.increment(1), updatedAt: now }, { merge: true });
    }

    const { alertAdmin } = deps.adminAlerts || require('./adminAlerts');
    if (outcome === 'failed') {
      alertAdmin({ key: 'email_failing', title: 'Emails are failing to send',
        body: `Neither the main mail server nor the SES backup delivered an email.\nLast error: ${(error && error.message) || 'unknown'}\nSee the admin dashboard → Messaging → Email delivery.`,
        email: false }); // email may be what's broken — the push and bell row still arrive
    } else if (outcome === 'fallback') {
      alertAdmin({ key: 'email_primary_down', minIntervalMs: 6 * 3600000, title: 'Main mail server is refusing — SES backup is sending',
        body: `mail.favcircles.com refused or didn't answer; Amazon SES delivered the email instead. Nothing is lost.\nMain server error: ${primaryError || 'unknown'}` });
    }
  } catch (e) {
    console.error(`[email-health] record ${outcome} failed: ${e.message}`);
  }
}

/** Log in to a route without sending anything; never throws. */
async function checkRoute(transporter, host, timeoutMs = 10000) {
  if (!transporter || typeof transporter.verify !== 'function') return { configured: false, host: host || null };
  const started = Date.now();
  try {
    await Promise.race([
      transporter.verify(),
      new Promise((_, reject) => setTimeout(() => reject(new Error(`no answer in ${timeoutMs / 1000}s`)), timeoutMs))
    ]);
    return { configured: true, host, ok: true, ms: Date.now() - started };
  } catch (error) {
    return { configured: true, host, ok: false, ms: Date.now() - started, error: error.message };
  }
}

async function liveStatus(deps = {}) {
  const emailService = deps.emailService || require('./emailService');
  const [primary, fallback] = await Promise.all([
    checkRoute(emailService.transporter, process.env.SMTP_HOST),
    checkRoute(emailService.fallbackTransporter, process.env.SMTP_FALLBACK_HOST)
  ]);
  return { primary, fallback, checkedAt: new Date().toISOString() };
}

/** The dashboard's Email delivery section: live checks + the last `days` days. */
async function dashboard({ days = 14 } = {}, deps = {}) {
  const db = deps.db || getFirestore();
  const keys = [];
  for (let i = days - 1; i >= 0; i--) keys.push(dayKey(new Date(Date.now() - i * 86400000)));
  const [status, snaps] = await Promise.all([
    liveStatus(deps),
    Promise.all(keys.map((k) => db.collection(COLLECTION).doc(k).get()))
  ]);
  const byDay = snaps.map((s, i) => {
    const d = s.exists ? s.data() : {};
    return { day: keys[i], primarySent: d.primarySent || 0, fallbackSent: d.fallbackSent || 0, failed: d.failed || 0, suppressed: d.suppressed || 0 };
  });
  const recentFailures = snaps.flatMap((s) => (s.exists && s.data().recentFailures) || []).sort((a, b) => (a.at < b.at ? 1 : -1)).slice(0, RECENT_FAILURES);
  const recentFallbacks = snaps.flatMap((s) => (s.exists && s.data().recentFallbacks) || []).sort((a, b) => (a.at < b.at ? 1 : -1)).slice(0, RECENT_FAILURES);
  const today = byDay[byDay.length - 1];
  return { status, today, byDay, recentFailures, recentFallbacks };
}

/** Hourly task: alert when a route can't even log in (catches outages on quiet hours). */
async function healthCheck(deps = {}) {
  const { alertAdmin } = deps.adminAlerts || require('./adminAlerts');
  const status = await liveStatus(deps);
  if (status.primary.configured && !status.primary.ok) {
    alertAdmin({ key: 'email_check_primary', minIntervalMs: 6 * 3600000, title: 'Main mail server check failed',
      body: `${status.primary.host}: ${status.primary.error}\n${status.fallback.ok ? 'The SES backup is working and will carry email.' : 'The SES backup is NOT working either — emails will fail.'}`,
      email: !!status.fallback.ok });
  }
  if (status.fallback.configured && !status.fallback.ok) {
    alertAdmin({ key: 'email_check_fallback', minIntervalMs: 6 * 3600000, title: 'SES backup mail check failed',
      body: `${status.fallback.host}: ${status.fallback.error}\nThe main server still sends; the backup just won't catch failures until this is fixed.` });
  }
  return status;
}

module.exports = { record, liveStatus, dashboard, healthCheck, dayKey };
