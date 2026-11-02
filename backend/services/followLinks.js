// services/followLinks.js
//
// Connected always means following (Wes, 2026-11-02), so Disconnect also ends
// the follow of the person who disconnects. Only theirs: the other person
// keeps following unless they choose otherwise — or the one disconnecting has
// a private profile, where the other has to ask again (Wes, 2026-11-02). One transaction keeps
// the arrays and their counts in step; nothing changes if they weren't
// following.

const { getFirestore } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');

async function removeFollow(followerId, targetId) {
  const db = getFirestore();
  const follower = normalizeUserId(followerId);
  const target = normalizeUserId(targetId);
  const followerRef = db.collection(COLLECTIONS.USERS).doc(follower);
  const targetRef = db.collection(COLLECTIONS.USERS).doc(target);
  await db.runTransaction(async (tx) => {
    const [followerDoc, targetDoc] = await Promise.all([tx.get(followerRef), tx.get(targetRef)]);
    if (!followerDoc.exists || !targetDoc.exists) return;
    if (!(followerDoc.data().following || []).includes(target)) return;
    const now = new Date().toISOString();
    tx.update(followerRef, { following: FieldValue.arrayRemove(target), followingCount: FieldValue.increment(-1), updatedAt: now });
    tx.update(targetRef, { followers: FieldValue.arrayRemove(follower), followersCount: FieldValue.increment(-1), updatedAt: now });
  });
}

module.exports = { removeFollow };
