// backend/services/userSearchService.js
//
// People search by name, one indexed read: every user doc carries
// `searchTokens` (word prefixes of displayName / firstName / lastName,
// utils/searchTokens). The two search endpoints used to disagree — one read
// the WHOLE users collection into a per-instance cache and substring-matched,
// the other prefix-queried `displayNameLowercase`, which only a profile edit
// ever wrote, so most accounts were invisible to it.
//
// Writers: createUser (models/FirestoreModels), updateUser, and the auth
// middleware, which heals any account whose fields are missing or stale (a
// rename through any other path) on its next request.
// scripts/backfill-user-search-tokens.js stamps everyone else.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { buildSearchTokens, queryTokens, anchorToken, hasAllTokens } = require('../utils/searchTokens');
const { isHiddenAccount, HIDDEN_ACCOUNT_FIELDS } = require('./hiddenAccounts');

// Candidates read per search before relevance ranking. Generous on purpose:
// the ranker (exact name, prefix, word) runs AFTER this cut, so a too-small
// window could drop the exact match among many "jo…" names.
const CANDIDATE_WINDOW = 300;

/** The text the tokens were built from — a mismatch means they are stale. */
const searchNameOf = (user) => [user.displayName, user.firstName, user.lastName]
  .filter(v => typeof v === 'string' && v.trim()).join(' | ');

/** Fields to write on a user doc so name search finds it. */
const userSearchFields = (user) => ({
  searchTokens: buildSearchTokens(user.displayName, user.firstName, user.lastName),
  searchName: searchNameOf(user),
  displayNameLowercase: typeof user.displayName === 'string' ? user.displayName.toLowerCase() : null
});

/** Do this user's stored search fields need (re)writing? */
const needsSearchFields = (user) =>
  Boolean(user) && (!Array.isArray(user.searchTokens) || user.searchName !== searchNameOf(user));

/**
 * Users whose name words start with every word of `term`, hidden accounts
 * removed and email never kept. Returns plain objects `{ id, ...fields }`;
 * the caller ranks, filters blocks and shapes the card.
 *
 * @param {string} term  raw search text
 * @param {object} [opts]
 * @param {string[]} [opts.fields]  card fields to read (select)
 */
async function findUsersByName(term, { fields = [], db = getFirestore(), window = CANDIDATE_WINDOW } = {}) {
  const tokens = queryTokens(term);
  if (tokens.length === 0) return [];
  const select = [...new Set(['displayName', 'firstName', 'lastName', 'searchTokens', ...fields, ...HIDDEN_ACCOUNT_FIELDS])];
  const snap = await db.collection(COLLECTIONS.USERS)
    .where('searchTokens', 'array-contains', anchorToken(tokens))
    .select(...select)
    .limit(window)
    .get();
  const out = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (isHiddenAccount(data)) continue;
    if (!hasAllTokens(data.searchTokens, tokens)) continue;
    const { email, searchTokens, ...rest } = data; // eslint-disable-line no-unused-vars
    out.push({ id: doc.id, ...rest });
  }
  return out;
}

// (id, name) pairs healed by this instance — one attempt each, so a failing
// write can't turn every request into a retry; a later rename heals again.
const healed = new Set();

/** Fire-and-forget: stamp missing or stale search fields on a user doc. */
function healUserSearchFields(userId, user, { db = getFirestore() } = {}) {
  if (!userId || !needsSearchFields(user)) return;
  const key = `${userId}|${searchNameOf(user)}`;
  if (healed.has(key)) return;
  healed.add(key);
  db.collection(COLLECTIONS.USERS).doc(userId).update(userSearchFields(user))
    .catch(err => console.warn(`⚠️ search fields for ${userId}: ${err.message}`));
}

function resetHealedForTests() { healed.clear(); }

module.exports = {
  userSearchFields, needsSearchFields, searchNameOf,
  findUsersByName, healUserSearchFields, resetHealedForTests, CANDIDATE_WINDOW
};
