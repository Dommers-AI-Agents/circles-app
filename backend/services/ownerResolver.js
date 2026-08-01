// Resolving "who owns this?" to an actual person.
//
// A circle stores its owner as a bare user id (`owner`). Three things make a
// naive `users.doc(owner).get()` unreliable:
//
//   1. Id format drift — the same person can appear under a Google numeric id,
//      a Firebase uid, or a legacy hex id (see utils/idNormalizer and the
//      account-merge work). A raw lookup misses those.
//   2. Deleted accounts — the id points at nothing, and callers that don't
//      notice render "Unknown" (or worse, expose an ownerless circle).
//   3. Repeated lookups — list endpoints resolve the same owner many times.
//
// This centralises all three so no caller has to remember them.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');

const db = getFirestore();

// Short-lived: long enough to dedupe a request's worth of lookups, short
// enough that a rename shows up promptly.
const CACHE_TTL_MS = 60 * 1000;
const cache = new Map(); // id -> { at, value }

const cached = (id) => {
  const hit = cache.get(id);
  if (!hit) return undefined;
  if (Date.now() - hit.at > CACHE_TTL_MS) {
    cache.delete(id);
    return undefined;
  }
  return hit.value;
};

const remember = (id, value) => {
  cache.set(id, { at: Date.now(), value });
  return value;
};

/// Alternate ids a user doc can be known by (linked auth providers, legacy uid
/// fields). Built lazily and cached — the users collection is small, and this
/// only runs when a direct lookup missed.
let altIndex = null;
let altIndexAt = 0;

async function buildAltIndex() {
  if (altIndex && Date.now() - altIndexAt < CACHE_TTL_MS) return altIndex;
  const index = new Map();
  const snap = await db.collection(COLLECTIONS.USERS).get();
  snap.docs.forEach((doc) => {
    const data = doc.data();
    Object.values(data.linkedProviders || {}).forEach((value) => {
      if (typeof value === 'string' && value) index.set(value, doc.id);
    });
    ['firebaseUid', 'uid', 'googleId', 'legacyId'].forEach((field) => {
      if (typeof data[field] === 'string' && data[field]) index.set(data[field], doc.id);
    });
  });
  altIndex = index;
  altIndexAt = Date.now();
  return index;
}

/**
 * Resolve a user id to its serialized user document.
 * Returns null when the person genuinely no longer exists — callers should
 * treat that as "ownerless", not as a display string.
 */
async function resolveUser(userId) {
  if (!userId || typeof userId !== 'string') return null;
  const hit = cached(userId);
  if (hit !== undefined) return hit;

  try {
    const direct = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (direct.exists) return remember(userId, serializeDoc(direct));

    // Not a doc id — maybe it's how another auth provider knows them.
    const index = await buildAltIndex();
    const mapped = index.get(userId);
    if (mapped) {
      const alt = await db.collection(COLLECTIONS.USERS).doc(mapped).get();
      if (alt.exists) return remember(userId, serializeDoc(alt));
    }
  } catch (error) {
    console.error(`⚠️ resolveUser(${userId}) failed:`, error.message);
    return null; // never cache a failure — it may be transient
  }

  return remember(userId, null);
}

/**
 * Attach `ownerDetails` to a serialized circle (mutates and returns it).
 * `isOwner` skips the lookup for your own circles, whose UI says "You".
 */
async function attachOwnerDetails(circle, { isOwner = false } = {}) {
  if (!circle || isOwner || !circle.owner) return circle;
  const owner = await resolveUser(circle.owner);
  if (owner) circle.ownerDetails = owner;
  // A circle whose owner no longer exists is orphaned. Say so explicitly so
  // clients can hide it rather than rendering "Shared by Unknown".
  else circle.ownerMissing = true;
  return circle;
}

/** Batch form for list endpoints — one lookup per distinct owner. */
async function attachOwnerDetailsToAll(circles, currentUserId) {
  const distinct = [...new Set((circles || []).map((c) => c && c.owner).filter(Boolean))];
  const resolved = new Map();
  await Promise.all(distinct.map(async (id) => resolved.set(id, await resolveUser(id))));
  (circles || []).forEach((circle) => {
    if (!circle || !circle.owner) return;
    if (currentUserId && circle.owner === currentUserId) return;
    const owner = resolved.get(circle.owner);
    if (owner) circle.ownerDetails = owner;
    else circle.ownerMissing = true;
  });
  return circles;
}

module.exports = { resolveUser, attachOwnerDetails, attachOwnerDetailsToAll };
