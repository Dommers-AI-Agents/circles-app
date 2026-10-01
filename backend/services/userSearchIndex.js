// The searchable fields of every account, cached per instance for a few
// minutes. User search used to read the whole users collection on EVERY
// search: fine at a few hundred accounts, a slow and costly read per keystroke
// at tens of thousands (viral-growth review, 2026-10-01). A new account
// becomes searchable within SEARCH_INDEX_TTL_MS. Public fields only — email
// and phone are never read (select()).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const TTL_MS = Number(process.env.SEARCH_INDEX_TTL_MS) || 5 * 60 * 1000;
let cache = null;      // { at, docs: [{ id, data }] }
let inFlight = null;

async function load(db) {
  const snap = await db.collection(COLLECTIONS.USERS)
    .select('displayName', 'firstName', 'lastName', 'profilePicture', 'bio', 'location', 'preferences')
    .get();
  return { at: Date.now(), docs: snap.docs.map((d) => { const data = d.data(); return { id: d.id, exists: true, data: () => data }; }) };
}

/** Docs shaped like Firestore snapshots ({ id, data() }) so callers loop as before. */
async function searchableUsers({ db = getFirestore(), now = Date.now() } = {}) {
  if (cache && now - cache.at < TTL_MS) return cache.docs;
  if (!inFlight) inFlight = load(db).then((c) => { cache = c; return c; }).finally(() => { inFlight = null; });
  return (await inFlight).docs;
}

function resetSearchIndexForTests() { cache = null; inFlight = null; }

module.exports = { searchableUsers, resetSearchIndexForTests };
