// services/circlePlacePrivacy.js
//
// A place's privacy always wins over its circle's (Wes, 2026-11-03). So when
// an owner changes a circle's privacy, the app asks whether to bring the
// circle's places along: "Make all N places Public too?" Yes sets each of the
// owner's places in it to follow the circle (so they also follow any later
// change); No leaves every place's own setting, which keeps winning.
//
// Only the circle owner's own saves: a place someone else added to a shared
// circle carries that person's privacy choice, not the owner's.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');
const { followsCircle, FOLLOW_CIRCLE } = require('./visibility');
const { isSameUser } = require('./idService');

/** The owner's live places in the circle that set their own privacy */
async function placesWithOwnPrivacy(circleId, ownerId, { db = getFirestore() } = {}) {
  const snap = await db.collection(COLLECTIONS.PLACES)
    .where('circleId', '==', circleId)
    .select('addedBy', 'privacy', 'deletedAt')
    .get();
  return snap.docs.filter(doc => {
    const p = doc.data();
    return !p.deletedAt && isSameUser(p.addedBy, ownerId) && !followsCircle(p);
  });
}

async function ownedCircle(circleId, userId, db) {
  const doc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
  if (!doc.exists) throw new ServiceError(404, 'circle_not_found', 'Circle not found');
  if (!isSameUser(doc.data().owner, userId)) throw new ServiceError(403, 'not_owner', 'Only the circle owner can do this');
  return doc;
}

/** How many of the owner's places in the circle have their own setting */
async function countOwnPrivacy(circleId, userId, { db = getFirestore() } = {}) {
  await ownedCircle(circleId, userId, db);
  return (await placesWithOwnPrivacy(circleId, userId, { db })).length;
}

/** Yes: every one of the owner's places in the circle follows the circle */
async function matchCircle(circleId, userId, { db = getFirestore() } = {}) {
  await ownedCircle(circleId, userId, db);
  const docs = await placesWithOwnPrivacy(circleId, userId, { db });
  const now = new Date().toISOString();
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach(doc => batch.update(doc.ref, { privacy: FOLLOW_CIRCLE, audienceListId: null, updatedAt: now }));
    await batch.commit();
  }
  return docs.length;
}

module.exports = { countOwnPrivacy, matchCircle, placesWithOwnPrivacy };
