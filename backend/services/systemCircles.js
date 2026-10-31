// backend/services/systemCircles.js
//
// The circles the app makes and finds for you — "Places I Follow",
// "Check-in Places", the starter "Favorite Local Spots" and "Want to Try",
// "Dog spots", "Places from my photos" — are found by a FLAG, never by their
// name (Wes, 2026-10-31: one source for every data point). Renaming one must
// not break the feature that uses it.
//
// The flag is `systemKind` on the circle doc. Kinds that already had a
// boolean keep writing it too, because indexed queries use it
// (owner + isCheckInCircle etc.). A doc counts as a kind when:
//   1. systemKind matches, or
//   2. its older marker matches (the kind's boolean, or for photos the
//      import markers), or
//   3. LEGACY ONLY: it has neither and its name is the kind's original name.
// A doc matched by 2 or 3 gets systemKind (and the boolean) stamped on it,
// one write, so the next lookup finds it by flag.
//
// No query on systemKind: an owner + systemKind query would need a new
// composite index. Lookups use the existing boolean query where one exists,
// else the owner's circles (single-equality) filtered here.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

// name = what the app names the circle when it makes one, and the legacy
// fallback for docs written before the flag.
const KINDS = {
  followedPlaces: { name: 'Places I Follow', boolean: 'isFollowedPlacesCircle' },
  checkIns: { name: 'Check-in Places', boolean: 'isCheckInCircle', preferFullest: true },
  favoriteLocal: { name: 'Favorite Local Spots', starter: true },
  wantToTry: { name: 'Want to Try', starter: true },
  dogSpots: { name: 'Dog spots', boolean: 'isDogSpotsCircle' },
  photoPlaces: { name: 'Places from my photos', marker: (c) => c.isImportCircle === true && c.importSource === 'photos' }
};
const KIND_NAMES = Object.keys(KINDS);

const spec = (kind) => {
  const s = KINDS[kind];
  if (!s) throw new Error(`unknown system circle kind: ${kind}`);
  return s;
};

/** The fields that make a new circle this kind. Spread them onto the doc AFTER createCircle (it drops unknown keys). */
function flagFields(kind) {
  const s = spec(kind);
  const out = { systemKind: kind };
  if (s.boolean) out[s.boolean] = true;
  return out;
}

/** Matched by its flag (or the kind's older marker), never by name. Pure. */
function hasFlag(circle, kind) {
  if (!circle) return false;
  const s = spec(kind);
  if (circle.systemKind === kind) return true;
  if (s.boolean && circle[s.boolean] === true) return true;
  return !!(s.marker && s.marker(circle));
}

/**
 * Legacy fallback only: a doc carrying no system flag at all whose name is the
 * kind's original name. Starter kinds also need isDefaultCircle (onboarding has
 * set it since the first release), so a circle someone named "Want to Try"
 * themselves is never adopted. Pure.
 */
function matchesLegacyName(circle, kind) {
  if (!circle || circle.systemKind) return false;
  const s = spec(kind);
  if (KIND_NAMES.some((k) => k !== kind && hasFlag(circle, k))) return false;
  if (s.starter && circle.isDefaultCircle !== true) return false;
  return typeof circle.name === 'string' && circle.name.trim() === s.name;
}

/** This circle is the kind (flag first, legacy name as fallback). Pure. */
function isKind(circle, kind) {
  return hasFlag(circle, kind) || matchesLegacyName(circle, kind);
}

/** Which kind this circle is, or null. Pure. */
function kindOf(circle) {
  if (!circle) return null;
  if (KINDS[circle.systemKind]) return circle.systemKind;
  return KIND_NAMES.find((k) => isKind(circle, k)) || null;
}

/** App-made, never someone's own curation (check-ins, follows). Pure. */
function isAppMadeCollection(circle) {
  return isKind(circle, 'checkIns') || isKind(circle, 'followedPlaces');
}

/** A starter circle from onboarding ("Want to Try", "Favorite Local Spots", "Vacation"). Pure. */
function isStarterCircle(circle) {
  if (!circle) return false;
  if (circle.isDefaultCircle === true) return true;
  if (isKind(circle, 'favoriteLocal') || isKind(circle, 'wantToTry')) return true;
  // Legacy: the starter names, from the one list onboarding creates them from
  // (lazy: data/popularPlaces takes its names from KINDS)
  const { DEFAULT_CIRCLES } = require('../data/popularPlaces');
  return !circle.systemKind && DEFAULT_CIRCLES.some((t) => t.name === circle.name);
}

const createdAtOf = (c) => String(c.createdAt || '');
const placeCount = (c) => (Array.isArray(c.places) ? c.places.length : 0) || c.placesCount || 0;

/**
 * The owner's circle of this kind from their circles ({ id, ...data } rows,
 * any order). Flagged first (oldest), else the legacy-name match (fullest
 * first for check-ins, then oldest). Deleted circles never count. Pure.
 * @returns {{ circle: object, needsStamp: boolean } | null}
 */
function pick(circles, kind) {
  const s = spec(kind);
  const alive = (circles || []).filter((c) => c && !c.deletedAt);
  const byAge = (a, b) => createdAtOf(a).localeCompare(createdAtOf(b));
  const flagged = alive.filter((c) => hasFlag(c, kind)).sort(byAge);
  if (flagged.length) return { circle: flagged[0], needsStamp: flagged[0].systemKind !== kind };
  const legacy = alive.filter((c) => matchesLegacyName(c, kind)).sort((a, b) => {
    if (s.preferFullest) {
      const diff = placeCount(b) - placeCount(a);
      if (diff !== 0) return diff;
    }
    return byAge(a, b);
  });
  return legacy.length ? { circle: legacy[0], needsStamp: true } : null;
}

/**
 * The single write that makes a matched doc carry its flag. Leaves updatedAt
 * alone: it isn't the person's edit, and some lists sort by updatedAt.
 */
async function stamp(circleId, kind, db = getFirestore()) {
  await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update(flagFields(kind));
}

/**
 * Pick from rows already loaded, stamping the flag when matched by an older
 * marker or the legacy name. Returns the circle row (flag fields merged) or null.
 */
async function pickAndHeal(circles, kind, { db = getFirestore() } = {}) {
  const hit = pick(circles, kind);
  if (!hit) return null;
  if (!hit.needsStamp) return hit.circle;
  try {
    await stamp(hit.circle.id, kind, db);
  } catch (error) {
    console.warn(`[systemCircles] could not stamp ${kind} on ${hit.circle.id}:`, error.message);
  }
  return { ...hit.circle, ...flagFields(kind) };
}

const rows = (snap) => snap.docs.map((d) => ({ id: d.id, ...d.data() }));

/**
 * The owner's circle of this kind, read from Firestore and self-healed.
 * Index-free: the kind's boolean query when it has one, else (or when that
 * finds nothing) the owner's circles.
 * @returns {Promise<object|null>} { id, ...data }
 */
async function findOwned(ownerId, kind, { db = getFirestore() } = {}) {
  const s = spec(kind);
  const circles = db.collection(COLLECTIONS.CIRCLES);
  if (s.boolean) {
    const snap = await circles.where('owner', '==', ownerId).where(s.boolean, '==', true).get();
    const hit = await pickAndHeal(rows(snap), kind, { db });
    if (hit) return hit;
  }
  const all = await circles.where('owner', '==', ownerId).get();
  return pickAndHeal(rows(all), kind, { db });
}

module.exports = {
  KINDS, KIND_NAMES, flagFields, hasFlag, matchesLegacyName, isKind, kindOf,
  isAppMadeCollection, isStarterCircle, pick, pickAndHeal, findOwned, stamp
};
