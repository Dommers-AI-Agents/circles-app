// services/placeReach.js
//
// Whose places a viewer could see on network surfaces (the map, network
// search, browse), for place-first queries (Wes, 2026-11-03: circles only
// organize; places carry the location and the privacy that matters).
//
// A candidate save is "in reach" when it was added by the viewer, by someone
// they're connected to or follow, or sits in a circle someone shared with the
// viewer by name. Whether it's actually SHOWN is then canSeePlace per save:
// its own privacy, or its circle's when it follows the circle.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');
const { canSeePlace } = require('./visibility');

/** @returns {{ people: string[], peopleSet: Set<string>, sharedCircleIds: string[] }} */
async function reachOf(userId, viewerCtx, { onlyPerson = null, db = getFirestore() } = {}) {
  if (onlyPerson) {
    const id = normalizeUserId(onlyPerson);
    return { people: [id], peopleSet: new Set([id]), sharedCircleIds: [] };
  }
  const people = [...new Set([userId, ...viewerCtx.connections, ...viewerCtx.following].map(normalizeUserId).filter(Boolean))];
  const shared = await db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', userId).select().get();
  return { people, peopleSet: new Set(people), sharedCircleIds: shared.docs.map(doc => doc.id) };
}

const inReach = (save, reach) =>
  reach.peopleSet.has(normalizeUserId(save.addedBy)) || reach.sharedCircleIds.includes(save.circleId);

/** The circles of these saves: privacy (for followCircle saves) + showOnMap */
async function circlesFor(saves, { db = getFirestore() } = {}) {
  const ids = [...new Set(saves.map(save => save.circleId).filter(Boolean))];
  const map = new Map();
  for (let i = 0; i < ids.length; i += 300) {
    const docs = await db.getAll(...ids.slice(i, i + 300).map(id => db.collection(COLLECTIONS.CIRCLES).doc(id)),
      { fieldMask: ['owner', 'privacy', 'sharedWith', 'audienceListId', 'showOnMap'] });
    docs.forEach(doc => { if (doc.exists) map.set(doc.id, doc.data()); });
  }
  return map;
}

/**
 * The saves among `saves` that a network surface may show this viewer: in
 * reach, in a circle that still exists (floating check-in places and saves of
 * deleted circles were never network items), and visible by the one rule.
 * `mapOnly` also honors a circle owner's "not on my map".
 */
async function visibleNetworkSaves(saves, { userId, viewerCtx, reach, mapOnly = false, db = getFirestore() }) {
  const candidates = saves.filter(save => !save.deletedAt && inReach(save, reach));
  const circles = await circlesFor(candidates, { db });
  return candidates.filter(save => {
    const circle = circles.get(save.circleId);
    if (!circle) return false;
    if (mapOnly && circle.showOnMap === false) return false;
    return canSeePlace(save, circle, userId, viewerCtx);
  });
}

module.exports = { reachOf, inReach, circlesFor, visibleNetworkSaves };
