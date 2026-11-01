// services/communityFeedActors.js
//
// The Activity tab is never empty (Wes, 2026-11-01): someone who follows
// fewer than a handful of people also sees what the most active mappers are
// adding. Only their PUBLIC activity reaches the viewer: the feed's privacy
// gates treat these people as strangers, as they are.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { isHiddenAccount } = require('./hiddenAccounts');
const { CORE_SUGGESTED_EMAILS } = require('./defaultAccounts');

/** Fewer people than this in a viewer's network → add the community */
const SPARSE_NETWORK = 5;
const COMMUNITY_SIZE = 25;
const TTL_MS = 30 * 60 * 1000;

let cache = null;

/** The founders plus the most active mappers, test accounts left out */
async function communityActorIds({ db = getFirestore(), now = Date.now() } = {}) {
  if (cache && now - cache.at < TTL_MS) return cache.ids;
  const [core, top] = await Promise.all([
    db.collection(COLLECTIONS.USERS).where('email', 'in', CORE_SUGGESTED_EMAILS).get(),
    db.collection(COLLECTIONS.USERS).orderBy('placesCount', 'desc').limit(COMMUNITY_SIZE * 2).get()
  ]);
  const ids = [];
  for (const doc of [...core.docs, ...top.docs]) {
    if (ids.length >= COMMUNITY_SIZE) break;
    if (ids.includes(doc.id) || isHiddenAccount(doc.data())) continue;
    ids.push(doc.id);
  }
  cache = { at: now, ids };
  return ids;
}

/**
 * Adds community actors to `actorIds` (a Set) when the viewer's own network
 * is sparse. `networkSize` counts the people they follow or are connected to.
 * @returns {Promise<string[]>} the ids added
 */
async function addCommunityIfSparse(actorIds, { viewerId, networkSize, db } = {}) {
  if (networkSize >= SPARSE_NETWORK) return [];
  const added = [];
  for (const id of await communityActorIds({ db })) {
    if (id === viewerId || actorIds.has(id)) continue;
    actorIds.add(id);
    added.push(id);
  }
  return added;
}

module.exports = { communityActorIds, addCommunityIfSparse, SPARSE_NETWORK, _reset: () => { cache = null; } };
