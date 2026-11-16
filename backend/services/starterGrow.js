// services/starterGrow.js — what the day 2 and day 5 "grow your map" nudges
// name (Wes, 2026-11-16: "suggest adding some new places near them to help
// their map grow, and showing other users to follow"). Real places saved near
// them and real people worth following, so the push says something instead of
// "follow a few people". The push opens My Network → Discover, which lists
// both (Places saved near you, People you might know).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { isHiddenAccount, HIDDEN_ACCOUNT_FIELDS } = require('./hiddenAccounts');
const { defaultFollowIds } = require('./defaultAccounts');

const MAX_NAMED = 2;
const MAX_PEOPLE = 5;

/** "Ra Sushi", "Ra Sushi and Fellini Cucina", "Ra Sushi, Fellini Cucina and 3 more" */
function listNames(names, total) {
  const shown = names.slice(0, MAX_NAMED);
  if (shown.length === 0) return '';
  const more = Math.max(0, (total || names.length) - shown.length);
  if (more > 0) return `${shown.join(', ')} and ${more} more`;
  return shown.join(' and ');
}

/** "Sunil Nat" → "Sunil" (a push reads better with first names) */
function firstName(name) {
  return String(name || '').trim().split(/\s+/)[0] || '';
}

/**
 * Pure (tested): the copy for a grow nudge. picks = { places: [name],
 * placeCount, people: [name], peopleCount }. Null when there's nothing real
 * to name, so the caller falls back to its generic copy.
 */
function growCopy(picks) {
  const p = picks || {};
  const places = (p.places || []).filter(Boolean);
  const people = (p.people || []).map(firstName).filter(Boolean);
  const placeLine = places.length ? listNames(places, p.placeCount) : '';
  const peopleLine = people.length ? listNames(people, p.peopleCount) : '';
  if (placeLine && peopleLine) {
    return `People near you love ${placeLine}. And ${peopleLine} ${people.length === 1 && !(p.peopleCount > 1) ? 'is' : 'are'} worth a follow.`;
  }
  if (placeLine) return `People near you love ${placeLine}. Save the ones you love too.`;
  if (peopleLine) return `${peopleLine} ${people.length === 1 && !(p.peopleCount > 1) ? 'is' : 'are'} worth a follow: every place they love shows up on your map.`;
  return null;
}

/**
 * People to suggest: the nightly suggestion engine's list first (it has a
 * reason for each), else whoever saves the most places near them. Never
 * themselves, anyone they follow, the default accounts, or test accounts.
 */
async function pickPeople(user, { db = getFirestore() } = {}) {
  const following = new Set(user.following || []);
  const defaults = await defaultFollowIds(db);
  const ok = (id) => id && id !== user.id && !following.has(id) && !defaults.has(id);

  let ids = [];
  const precomputed = await require('./suggestionEngine').getSuggestionsFor(user.id).catch(() => null);
  if (precomputed && precomputed.length) ids = precomputed.map((s) => s.userId).filter(ok);
  if (ids.length === 0) {
    const localPeople = require('./localPeople');
    const center = await localPeople.viewerCenter(user.id, user);
    const counts = await localPeople.localSaverCounts(center);
    ids = [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([id]) => id).filter(ok);
  }
  const candidates = ids.slice(0, MAX_PEOPLE * 2);
  if (candidates.length === 0) return [];
  const docs = await db.getAll(...candidates.map((id) => db.collection(COLLECTIONS.USERS).doc(id)),
    { fieldMask: [...HIDDEN_ACCOUNT_FIELDS, 'displayName'] });
  return docs.filter((d) => d.exists && !isHiddenAccount(d.data()) && d.data().displayName)
    .slice(0, MAX_PEOPLE)
    .map((d) => ({ id: d.id, name: d.data().displayName }));
}

/** Places saved near them (the Discover page's own list), names only. */
async function pickPlaces(user) {
  const rows = await require('./networkLovedPlaces').nearbyForViewer(user.id, { limit: 10 });
  // Never suggest a place they already have
  return rows.filter((r) => r.name && r.name !== 'Place' && !r.viewerSaved).map((r) => r.name);
}

/** Both, for one user. Each half fails on its own (a push still goes). */
async function growPicks(user, options = {}) {
  const [places, people] = await Promise.all([
    pickPlaces(user).catch((e) => { console.error('🌱 grow places:', e.message); return []; }),
    pickPeople(user, options).catch((e) => { console.error('🌱 grow people:', e.message); return []; })
  ]);
  return {
    places: places.slice(0, MAX_NAMED), placeCount: places.length,
    people: people.slice(0, MAX_NAMED).map((x) => x.name), peopleCount: people.length
  };
}

module.exports = { growCopy, growPicks, listNames, firstName };
