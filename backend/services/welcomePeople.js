// backend/services/welcomePeople.js
//
// "Also loves Fresh Monkee": the people who saved a place a new user saved,
// for the first-run people list (userDiscoveryController type=welcome,
// 2026-11-07). Only saves the new user may see count (services/visibility
// canSeePlace, with no relationship yet — so public ones), so the list never
// reveals a private save.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { canSeePlace } = require('./visibility');
const { queryInChunks } = require('../utils/firestoreChunks');

const MAX_OWN_PLACES = 20;

/** userId → the name of one place they share with `userId` (their newest saves first). */
async function sharedPlaceSavers(userId, { db = getFirestore() } = {}) {
  const out = new Map();
  try {
    const own = await db.collection(COLLECTIONS.PLACES).where('addedBy', '==', String(userId))
      .select('globalPlaceId', 'name', 'deletedAt', 'createdAt').get();
    const mine = own.docs.map((d) => d.data())
      .filter((p) => p.globalPlaceId && !p.deletedAt)
      .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')))
      .slice(0, MAX_OWN_PLACES);
    if (!mine.length) return out;
    const nameOf = new Map(mine.map((p) => [p.globalPlaceId, p.name]));
    const saves = (await queryInChunks([...nameOf.keys()], (chunk) =>
      db.collection(COLLECTIONS.PLACES).where('globalPlaceId', 'in', chunk)
        .select('globalPlaceId', 'addedBy', 'circleId', 'privacy', 'sharedWith', 'audienceListId', 'deletedAt').get()))
      .map((d) => d.data())
      .filter((p) => p.addedBy && String(p.addedBy) !== String(userId) && !p.deletedAt);
    const circleIds = [...new Set(saves.map((p) => p.circleId).filter(Boolean))];
    const circles = new Map();
    if (circleIds.length) {
      const docs = await db.getAll(...circleIds.map((id) => db.collection(COLLECTIONS.CIRCLES).doc(String(id))));
      docs.filter((d) => d.exists).forEach((d) => circles.set(d.id, d.data()));
    }
    for (const save of saves) {
      if (out.has(String(save.addedBy))) continue;
      if (!canSeePlace(save, circles.get(save.circleId), userId)) continue;
      out.set(String(save.addedBy), nameOf.get(save.globalPlaceId));
    }
  } catch (error) {
    console.warn('⚠️ Welcome shared-place lookup failed (list continues):', error.message);
  }
  return out;
}

module.exports = { sharedPlaceSavers };
