// backend/services/dailyBudget.js
//
// Per-user daily allowances for actions that cost money or reach people who
// never asked to hear from us: user-triggered outbound email (contact
// invites, connection-request emails, postcard emails), paid Google Places
// lookups from check-ins, and new connection requests.
//
// Security audit 2026-10-01: each of those could be looped by one account —
// a script re-sending invites or connection requests mailed strangers from
// our SMTP domain (deliverability for everyone), and fake check-in names
// billed Find Place + Details + Photo per call. The limits sit far above
// what a person does in a day, so normal use never sees them.
//
// One Firestore doc per user, bucket and UTC day —
// dailyBudgets/{bucket}_{uid}_{YYYY-MM-DD} — incremented in a transaction so
// concurrent requests can't both slip under the cap. Old docs are tiny and
// self-describing (bucket/userId/day); nothing reads past today.

const { getFirestore } = require('../config/firebase');

const COLLECTION = 'dailyBudgets';

// name → { env var, default limit, what to do if Firestore itself fails }.
// Email and connection requests fail OPEN (a Firestore blip must not stop a
// person inviting a friend); paid lookups fail CLOSED (skipping enrichment
// only costs a photo, never the check-in).
const BUCKETS = {
  // Sized so an enthusiastic real person never hits them (viral invites), only scripts
  email: { env: 'EMAIL_DAILY_BUDGET', limit: 100, failOpen: true },
  placesLookup: { env: 'PLACES_LOOKUP_DAILY_BUDGET', limit: 30, failOpen: false },
  connectionRequest: { env: 'CONNECTION_REQUEST_DAILY_BUDGET', limit: 200, failOpen: true }
};

const dayKey = (now = new Date()) => now.toISOString().slice(0, 10);

function limitFor(bucket) {
  const spec = BUCKETS[bucket];
  if (!spec) throw new Error(`dailyBudget: unknown bucket ${bucket}`);
  const fromEnv = parseInt(process.env[spec.env], 10);
  return Number.isFinite(fromEnv) && fromEnv >= 0 ? fromEnv : spec.limit;
}

/**
 * Spend `amount` units of a user's allowance for today. All-or-nothing:
 * when the whole amount doesn't fit, nothing is spent.
 * @returns {Promise<{allowed: boolean, used: number, limit: number}>}
 */
async function consume(bucket, userId, amount = 1, { now = new Date() } = {}) {
  const limit = limitFor(bucket);
  if (!userId) return { allowed: false, used: 0, limit };
  const db = getFirestore();
  const day = dayKey(now);
  const ref = db.collection(COLLECTION).doc(`${bucket}_${userId}_${day}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.exists && snap.data().count) || 0;
      if (used + amount > limit) return { allowed: false, used, limit };
      tx.set(ref, { bucket, userId, day, count: used + amount, updatedAt: now.toISOString() });
      return { allowed: true, used: used + amount, limit };
    });
  } catch (error) {
    console.error(`⚠️ dailyBudget ${bucket} check failed for ${userId}:`, error.message);
    return { allowed: BUCKETS[bucket].failOpen, used: 0, limit };
  }
}

module.exports = {
  consume,
  limitFor,
  dayKey,
  BUCKETS,
  // Named shorthands so call sites read as what they spend.
  consumeEmail: (userId, amount = 1) => consume('email', userId, amount),
  consumePlacesLookup: (userId) => consume('placesLookup', userId, 1),
  consumeConnectionRequest: (userId) => consume('connectionRequest', userId, 1)
};
