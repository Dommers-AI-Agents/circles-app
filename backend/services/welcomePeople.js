// backend/services/welcomePeople.js
//
// "Also loves Fresh Monkee": the people who saved a place a new user saved,
// for the first-run people list (userDiscoveryController type=welcome,
// 2026-11-07). Only saves the new user may see count (services/visibility
// canSeePlace, with no relationship yet — so public ones), so the list never
// reveals a private save. `rankWelcomePeople` is the order of that list.

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

// The fewest people the first-run list should offer. Below this the list is
// topped up with the biggest maps anywhere, so a new user in a town nobody
// has mapped yet doesn't get an empty page.
const MIN_WELCOME_PEOPLE = 6;

/**
 * The order of a new user's first people (Wes, 2026-11-25: "people near me
 * with the most places saved" — the list had offered someone with a big map
 * and nothing in the user's city). Pure.
 *
 * 1. People who save places near the user, most nearby places first. Saving
 *    a place the user saved, then recent activity, break ties.
 * 2. People who saved a place the user saved, wherever their other places are.
 * 3. Only when 1 and 2 leave fewer than MIN_WELCOME_PEOPLE: the biggest maps
 *    anywhere, with no claim that they are nearby.
 *
 * @param {Array<{id:string, localCount?:number, placesCount?:number, sharedPlaceName?:string|null, activeBonus?:number}>} candidates
 * @returns {Array<object>} the candidates to show, in order, each with `reason`
 */
function rankWelcomePeople(candidates, { min = MIN_WELCOME_PEOPLE } = {}) {
  const byMap = (a, b) => ((b.placesCount || 0) + (b.activeBonus || 0)) - ((a.placesCount || 0) + (a.activeBonus || 0));
  const local = candidates.filter((c) => (c.localCount || 0) > 0).sort((a, b) =>
    ((b.localCount || 0) - (a.localCount || 0))
    || ((b.sharedPlaceName ? 1 : 0) - (a.sharedPlaceName ? 1 : 0))
    || byMap(a, b));
  const shared = candidates.filter((c) => !((c.localCount || 0) > 0) && c.sharedPlaceName).sort(byMap);
  const relevant = [...local, ...shared];
  const filler = relevant.length >= min ? [] : candidates
    .filter((c) => !((c.localCount || 0) > 0) && !c.sharedPlaceName)
    .sort(byMap)
    .slice(0, min - relevant.length);
  return [...relevant, ...filler].map((c) => ({
    ...c,
    reason: c.sharedPlaceName ? `Also loves ${c.sharedPlaceName}`
      : (c.localCount || 0) > 0 ? 'Saves places near you'
        : null
  }));
}

module.exports = { sharedPlaceSavers, rankWelcomePeople, MIN_WELCOME_PEOPLE };
