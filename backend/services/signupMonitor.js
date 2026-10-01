// Watches new accounts for bot-like patterns and tells the admin — it never
// blocks anyone (signing up must stay easy). Two signals:
//   - a burst: SIGNUP_BURST_THRESHOLD+ new accounts from one IP in an hour;
//   - a throwaway email domain.
// Security audit 2026-10-01: there was no signal at all for fake accounts.
const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');

const DISPOSABLE = new Set([
  'mailinator.com', 'guerrillamail.com', 'guerrillamail.net', '10minutemail.com', 'tempmail.com', 'temp-mail.org',
  'yopmail.com', 'trashmail.com', 'getnada.com', 'dispostable.com', 'sharklasers.com', 'maildrop.cc',
  'throwawaymail.com', 'fakeinbox.com', 'mailnesia.com', 'mintemail.com', 'emailondeck.com', 'mohmal.com'
]);

const domainOf = (email) => String(email || '').toLowerCase().split('@')[1] || '';
const isDisposable = (email) => DISPOSABLE.has(domainOf(email));

/** Never throws; fire-and-forget from the signup paths. */
async function recordSignup({ ip, email, provider, userId }, deps = {}) {
  try {
    const db = deps.db || getFirestore();
    const { alertAdmin } = deps.adminAlerts || require('./adminAlerts');
    const threshold = Number(process.env.SIGNUP_BURST_THRESHOLD) || 5;
    if (isDisposable(email)) {
      alertAdmin({ key: `signup_disposable_${userId}`, minIntervalMs: 0, title: 'Signup with a throwaway email',
        body: `${email} (${provider || 'password'}) — user ${userId}` });
    }
    if (!ip) return;
    const ipKey = crypto.createHash('sha256').update(String(ip)).digest('hex').slice(0, 16);
    const hour = new Date().toISOString().slice(0, 13);
    const ref = db.collection('signupCounters').doc(`${ipKey}_${hour}`);
    const count = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const prev = snap.exists ? snap.data() : { count: 0, users: [] };
      const next = { count: prev.count + 1, users: [...(prev.users || []), `${userId} ${email || ''}`].slice(-20), expiresAt: new Date(Date.now() + 2 * 86400000) };
      tx.set(ref, next);
      return next.count;
    });
    if (count === threshold) {
      const users = ((await ref.get()).data() || {}).users || [];
      alertAdmin({ key: `signup_burst_${ipKey}`, minIntervalMs: 6 * 3600000, title: `${count} signups from one IP in an hour`,
        body: `IP hash ${ipKey}\n${users.join('\n')}` });
    }
  } catch (error) {
    console.error(`[signup-monitor] ${error.message}`);
  }
}

module.exports = { recordSignup, isDisposable };
