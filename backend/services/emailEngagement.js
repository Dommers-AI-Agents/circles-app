// backend/services/emailEngagement.js
//
// Records what people do with our email: one emailEvents row per click or
// open (never pruned) and a per-person rollup at
// users/{uid}/private/emailEngagement.{kind}.{clicks,opens,lastClickAt,
// lastOpenAt,lastUrl} so "did John click?" is one read. The recipient is
// matched to a user by email (relay addresses included); an email with no
// account (a store contact, an event guest) is recorded by email only.
//
// Opens are a weak signal: Apple Mail Privacy Protection fetches the pixel
// on delivery for most of our users. Clicks are the real one.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

async function userIdForEmail(email, db) {
  const snap = await db.collection(COLLECTIONS.USERS).where('email', '==', email).limit(1).get();
  return snap.empty ? null : snap.docs[0].id;
}

/**
 * @param {'click'|'open'} event
 * @param {{ sendId, to, kind, url? }} params  verified by emailTracking.readParams
 */
async function record(event, params, { userAgent = '', db = getFirestore(), now = () => new Date() } = {}) {
  const { FieldValue } = require('firebase-admin/firestore');
  const at = now().toISOString();
  const email = String(params.to || '').toLowerCase();
  const uid = await userIdForEmail(email, db).catch(() => null);
  await db.collection('emailEvents').add({
    event, email, uid, kind: params.kind, sendId: params.sendId,
    url: params.url || null, userAgent: String(userAgent || '').slice(0, 300), at
  });
  if (uid) {
    const field = event === 'click' ? 'clicks' : 'opens';
    const update = {
      [`${params.kind}.${field}`]: FieldValue.increment(1),
      [`${params.kind}.${event === 'click' ? 'lastClickAt' : 'lastOpenAt'}`]: at,
      updatedAt: at
    };
    if (event === 'click') update[`${params.kind}.lastUrl`] = params.url || null;
    const ref = db.collection(COLLECTIONS.USERS).doc(uid).collection('private').doc('emailEngagement');
    await ref.set({}, { merge: true });
    await ref.update(update);
  }
  console.log(`📧 ${event} ${params.kind} ${email}${uid ? ` (${uid})` : ''}${params.url ? ` → ${params.url}` : ''}`);
  return { uid, at };
}

module.exports = { record, userIdForEmail };
