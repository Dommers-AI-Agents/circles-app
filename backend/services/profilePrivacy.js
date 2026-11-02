// services/profilePrivacy.js
//
// Public vs private profiles (Wes, 2026-11-02), like Instagram:
//   * A PUBLIC profile (the default) shows its public-tier circles, places and
//     moments to anyone who opens it — that is how people decide to follow.
//   * A PRIVATE profile shows them only to followers and connections; anyone
//     else sees the name, photo and counts, and following needs approval
//     (services/followRequestService.js).
// Either way, updates (the activity feed) reach only followers and
// connections — see services/activityPrivacy.js.
//
// `users.profilePrivate === true` is the stored flag. visibility.canViewAtTier
// is synchronous and runs thousands of times a request, so the private
// accounts are held in memory: loaded once before the first request
// (`ready()`, awaited by middleware in server.js), refreshed every minute, and
// updated at once on this instance when someone flips the switch. Another
// instance catches up within REFRESH_MS. Private accounts are few, so the set
// stays small.
//
// Until the first load succeeds every account is treated as private — a
// stranger briefly seeing less is the safe direction.

// Firestore modules are required inside load(): FirestoreModels reaches
// visibility.js, which requires this file at load time.
const { normalizeUserId } = require('./idService');

const REFRESH_MS = 60 * 1000;

let privateIds = null;          // Set of normalized ids, null until first load
let loading = null;
let timer = null;

async function load(db = require('../config/firebase').getFirestore()) {
  const { COLLECTIONS } = require('../models/FirestoreModels');
  const snap = await db.collection(COLLECTIONS.USERS).where('profilePrivate', '==', true).select().get();
  privateIds = new Set(snap.docs.map((d) => normalizeUserId(d.id)).filter(Boolean));
  return privateIds;
}

/** Resolves once the set has loaded (retries on the next call after a failure). */
function ready() {
  if (privateIds) return Promise.resolve(privateIds);
  if (!loading) {
    loading = load()
      .catch((e) => { console.error('⚠️ profilePrivacy load failed:', e.message); return null; })
      .finally(() => { loading = null; });
    if (!timer) {
      timer = setInterval(() => { load().catch((e) => console.error('⚠️ profilePrivacy refresh failed:', e.message)); }, REFRESH_MS);
      if (timer.unref) timer.unref();
    }
  }
  return loading;
}

/** Is this account's profile private? Unknown (not loaded yet) counts as private. */
function isPrivateProfile(userId) {
  if (!privateIds) return true;
  return privateIds.has(normalizeUserId(userId));
}

/** Record a change made on this instance so it applies before the next refresh. */
function noteProfilePrivacy(userId, isPrivate) {
  if (!privateIds) return;
  const id = normalizeUserId(userId);
  if (isPrivate) privateIds.add(id); else privateIds.delete(id);
}

/** Express middleware: hold the first requests until the set has loaded (5 s cap). */
function profilePrivacyReady(req, res, next) {
  if (privateIds) return next();
  let done = false;
  const go = () => { if (!done) { done = true; next(); } };
  setTimeout(go, 5000);
  ready().then(go, go);
}

module.exports = {
  isPrivateProfile, noteProfilePrivacy, ready, profilePrivacyReady,
  _setForTests: (ids) => { privateIds = ids ? new Set([...ids].map(normalizeUserId)) : null; }
};
