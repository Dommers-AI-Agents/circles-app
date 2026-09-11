// backend/services/checkInStatsService.js
//
// Per-user, per-venue check-in history ("you've checked in here 7 times, last
// on Sep 5"). Kept as a tiny aggregate so the place page reads ONE doc instead
// of counting check-ins:
//
//   users/{uid}/checkInStats/{globalPlaceId} = { count, firstCheckInAt,
//                                                lastCheckInAt, placeName,
//                                                lastPlaceId, lastCheckInId }
//
// Venue identity is the canonical globalPlaces id — a check-in at a venue you
// saved in two circles, or typed by name, all land in the same bucket. Only
// the viewer's own stats are ever served (see getMyCheckInStats); nothing here
// is social.
//
// scripts/backfill-checkin-stats.js rebuilds the aggregate from raw checkIns
// docs (idempotent, DRY_RUN=true); the live path below increments in place.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const {
  ensureGlobalPlaceLink,
  findCanonicalByNameAndLocation
} = require('./globalPlaceResolver');

const db = getFirestore();

const statsRef = (userId, globalPlaceId) => db
  .collection(COLLECTIONS.USERS).doc(userId)
  .collection(COLLECTIONS.CHECK_IN_STATS).doc(globalPlaceId);

// Pure: fold one check-in (ISO timestamp) into an existing aggregate. Used by
// both the live transaction and the backfill so they can't drift.
const applyCheckIn = (existing, { at, placeName, placeId, checkInId }) => {
  const prev = existing || {};
  const first = prev.firstCheckInAt && prev.firstCheckInAt < at ? prev.firstCheckInAt : at;
  const last = prev.lastCheckInAt && prev.lastCheckInAt > at ? prev.lastCheckInAt : at;
  const isNewest = last === at;
  return {
    count: (prev.count || 0) + 1,
    firstCheckInAt: first,
    lastCheckInAt: last,
    placeName: isNewest ? (placeName || prev.placeName || null) : (prev.placeName || placeName || null),
    lastPlaceId: isNewest ? (placeId || prev.lastPlaceId || null) : (prev.lastPlaceId || placeId || null),
    lastCheckInId: isNewest ? (checkInId || prev.lastCheckInId || null) : (prev.lastCheckInId || checkInId || null)
  };
};

// Which venue was this check-in at? Prefer the save record's canonical link
// (linking it on demand for pre-normalization saves); fall back to a
// name+proximity match against globalPlaces for typed venues. Returns null
// when the venue can't be identified (no save and no coordinates).
async function resolveCheckInVenue({ placeId, placeName, location, allowWrites = true }) {
  if (placeId) {
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (placeDoc.exists) {
      const data = placeDoc.data();
      if (data.globalPlaceId) return data.globalPlaceId;
      if (allowWrites && !data.deletedAt) {
        const linked = await ensureGlobalPlaceLink(placeDoc);
        if (linked) return linked;
      }
      // A trashed/unlinked save still names the venue — fall through to the
      // name match using the save's own coordinates when the check-in has none
      if (!location && data.location) location = data.location;
      if (!placeName) placeName = data.name;
    }
  }
  const coords = location && (
    Array.isArray(location.coordinates) ? location.coordinates
      : (typeof location.longitude === 'number' && typeof location.latitude === 'number')
        ? [location.longitude, location.latitude]
        : null
  );
  if (!placeName || !coords) return null;
  const canonical = await findCanonicalByNameAndLocation(placeName, { coordinates: coords });
  return canonical ? canonical.id : null;
}

// Live path: one transaction on the aggregate doc. Never throws — a stats
// hiccup must not fail a check-in.
async function recordCheckIn({ userId, globalPlaceId, checkInId, placeId, placeName, at }) {
  if (!userId || !globalPlaceId) return null;
  const when = at || new Date().toISOString();
  try {
    const ref = statsRef(userId, globalPlaceId);
    const next = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const merged = applyCheckIn(snap.exists ? snap.data() : null, {
        at: when, placeName, placeId, checkInId
      });
      tx.set(ref, { ...merged, globalPlaceId, updatedAt: new Date().toISOString() });
      return merged;
    });
    return next;
  } catch (error) {
    console.error(`⚠️ [CheckInStats] Failed to record check-in for ${userId}/${globalPlaceId}:`, error.message);
    return null;
  }
}

// The API shape served to iOS. Null when the viewer has never checked in here.
const toApi = (data) => (data && data.count > 0 ? {
  count: data.count,
  firstCheckInAt: data.firstCheckInAt || null,
  lastCheckInAt: data.lastCheckInAt || null
} : null);

async function getMyCheckInStats(userId, globalPlaceId) {
  if (!userId || !globalPlaceId) return null;
  try {
    const snap = await statsRef(userId, globalPlaceId).get();
    return snap.exists ? toApi(snap.data()) : null;
  } catch (error) {
    console.error(`⚠️ [CheckInStats] Failed to read stats for ${userId}/${globalPlaceId}:`, error.message);
    return null;
  }
}

module.exports = {
  applyCheckIn,
  resolveCheckInVenue,
  recordCheckIn,
  getMyCheckInStats,
  toApi,
  statsRef
};
