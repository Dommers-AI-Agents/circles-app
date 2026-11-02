// services/followLinks.js
//
// Connected always means following (Wes, 2026-11-02), so Disconnect ends the
// follow in both directions too. One transaction keeps the arrays and their
// counts in step; a side that wasn't following is left alone.

const { getFirestore } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');

async function removeFollowsBetween(a, b) {
  const db = getFirestore();
  const idA = normalizeUserId(a);
  const idB = normalizeUserId(b);
  const refA = db.collection(COLLECTIONS.USERS).doc(idA);
  const refB = db.collection(COLLECTIONS.USERS).doc(idB);
  await db.runTransaction(async (tx) => {
    const [docA, docB] = await Promise.all([tx.get(refA), tx.get(refB)]);
    if (!docA.exists || !docB.exists) return;
    const now = new Date().toISOString();
    const aFollowsB = (docA.data().following || []).includes(idB);
    const bFollowsA = (docB.data().following || []).includes(idA);
    const updA = { updatedAt: now };
    const updB = { updatedAt: now };
    if (aFollowsB) {
      Object.assign(updA, { following: FieldValue.arrayRemove(idB), followingCount: FieldValue.increment(-1) });
      Object.assign(updB, { followers: FieldValue.arrayRemove(idA), followersCount: FieldValue.increment(-1) });
    }
    if (bFollowsA) {
      Object.assign(updB, { following: FieldValue.arrayRemove(idA), followingCount: FieldValue.increment(-1) });
      Object.assign(updA, { followers: FieldValue.arrayRemove(idB), followersCount: FieldValue.increment(-1) });
    }
    if (aFollowsB || bFollowsA) {
      tx.update(refA, updA);
      tx.update(refB, updB);
    }
  });
}

module.exports = { removeFollowsBetween };
