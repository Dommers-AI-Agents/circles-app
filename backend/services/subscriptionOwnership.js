// backend/services/subscriptionOwnership.js
//
// One App Store subscription, one FavCircles account (Wes, 2026-11-07: a new
// test account on his phone became Premium from his own subscription). The
// app sends the phone's receipt on every launch, and verify used to attach it
// to whichever account was signed in — so one purchase unlocked any number of
// accounts, and Apple's renewal notices (looked up by the transaction id)
// found two accounts.
//
// Now the account that holds it first keeps it. Another account on the same
// Apple ID gets told where it is and can move it with an explicit tap
// (`transferSubscription: true`), which takes it off the old account.

const { FieldValue } = require('firebase-admin/firestore');

/** "sgroiwes@gmail.com" → "s•••@gmail.com". Pure. */
function maskEmail(email) {
  const e = String(email || '');
  const at = e.indexOf('@');
  if (at < 1) return null;
  return `${e[0]}•••${e.slice(at)}`;
}

/** A live account other than `userId` that holds this subscription, or null. */
async function otherHolder(db, originalTransactionId, userId) {
  if (!originalTransactionId) return null;
  const snap = await db.collection('users')
    .where('appleOriginalTransactionId', '==', String(originalTransactionId)).limit(10).get();
  const doc = snap.docs.find((d) => {
    const u = d.data();
    return d.id !== String(userId) && !u.mergedInto && u.active !== false && !u.isDeleted;
  });
  return doc ? { id: doc.id, email: doc.data().email || null } : null;
}

/** Takes the subscription off `fromUserId` (moved to `toUserId`). */
async function release(db, fromUserId, toUserId, { now = new Date() } = {}) {
  await db.collection('users').doc(String(fromUserId)).update({
    subscriptionStatus: 'expired',
    subscriptionExpiryDate: now.toISOString(),
    appleOriginalTransactionId: FieldValue.delete(),
    subscriptionMovedTo: String(toUserId),
    subscriptionMovedAt: now.toISOString()
  });
}

/**
 * What verify should do with a consumer receipt for `userId`:
 *   { action: 'apply' }                        nobody else holds it (or this account already does)
 *   { action: 'blocked', emailHint }           another account holds it; not moved
 *   { action: 'moved', from }                  moved here on request (old account released)
 */
async function decide(db, { originalTransactionId, userId, alreadyHeldHere, transfer }) {
  if (alreadyHeldHere) return { action: 'apply' };
  const holder = await otherHolder(db, originalTransactionId, userId);
  if (!holder) return { action: 'apply' };
  if (!transfer) return { action: 'blocked', emailHint: maskEmail(holder.email) };
  await release(db, holder.id, userId);
  return { action: 'moved', from: holder.id };
}

module.exports = { maskEmail, otherHolder, release, decide };
