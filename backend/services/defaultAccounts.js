// services/defaultAccounts.js — the accounts every new user follows at signup
// (Wes and Brittany). One list, so "following people" checks, suggestions and
// onboarding agree on who they are.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const DEFAULT_FOLLOW_EMAILS = [
  'sgroiwes@gmail.com',      // Wes
  'brittanyvans@gmail.com'   // Brittany
];

let cached = null;

/** Their user ids (cached once found; a miss is never remembered). */
async function defaultFollowIds(db = getFirestore()) {
  if (cached) return cached;
  const snap = await db.collection(COLLECTIONS.USERS).where('email', 'in', DEFAULT_FOLLOW_EMAILS).get();
  const ids = new Set(snap.docs.map(d => d.id));
  if (ids.size > 0) cached = ids;
  return ids;
}

/** Pure: how many of `following` are people they chose (not the defaults). */
function chosenFollowCount(following, defaultIds) {
  return (Array.isArray(following) ? following : []).filter(id => !defaultIds.has(id)).length;
}

module.exports = { DEFAULT_FOLLOW_EMAILS, defaultFollowIds, chosenFollowCount, _reset: () => { cached = null; } };
